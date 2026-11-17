defmodule BrdcLedger.Assets do
  @moduledoc """
  Bens e propriedade (Fase 5, ADR-0018): classes com órgão M-de-N, registro, negociação direta
  com escrow e janela de veto, e gravames. **Puro**: `(estado, remetente, tipo, carga) → estado'`;
  o "agora" é o horário do bloco (`state.time`, ADR-0016).

  Tipos de transação: `5` classe · `6` registro · `7` oferta · `8` aceite · `9` cancelamento ·
  `10` veto · `11` finalização · `12` gravame · `13` remoção de gravame.

  Toda aprovação do órgão assina um documento que inclui a **revisão** do bem (`rev`), que sobe a
  cada ação do órgão: uma aprovação nunca vale duas vezes.
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.{Approvals, Params, State}

  @max_u64 0xFFFFFFFFFFFFFFFF
  @list_approvals {:list, :bytes}

  @doc "Tipos de transação deste módulo."
  @spec kinds() :: Range.t()
  def kinds, do: 5..13

  @doc "Taxa mínima por tipo (ADR-0014/0018): registro e classe, etapa da negociação, ou zero (órgão)."
  @spec min_fee(Params.t(), 5..13) :: non_neg_integer()
  def min_fee(%Params{} = p, kind) when kind in [5, 6], do: p.asset_register_fee
  def min_fee(%Params{} = p, kind) when kind in [7, 8, 9, 11], do: p.asset_step_fee
  def min_fee(%Params{}, _kind), do: 0

  @doc "Documento que as autoridades raiz aprovam para criar uma classe."
  @spec class_doc(String.t(), String.t(), [binary()], pos_integer(), pos_integer()) :: binary()
  def class_doc(chain, id, organ, threshold, veto_window) do
    doc(
      "class",
      [:string, :string, {:list, {:fixed, 32}}, :u32, :u64],
      [chain, id, organ, threshold, veto_window]
    )
  end

  @doc "Documento que o órgão aprova para registrar um bem."
  @spec register_doc(String.t(), String.t(), String.t(), binary(), binary()) :: binary()
  def register_doc(chain, class, asset, owner, meta) do
    doc("register", [:string, :string, :string, {:fixed, 32}, :bytes], [
      chain,
      class,
      asset,
      owner,
      meta
    ])
  end

  @doc "Documento que o órgão aprova para vetar uma negociação (amarra bem, revisão, comprador, preço e prazo)."
  @spec veto_doc(
          String.t(),
          String.t(),
          non_neg_integer(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          binary()
  def veto_doc(chain, asset, rev, buyer, price, deadline) do
    doc("veto", [:string, :string, :u64, {:fixed, 32}, :u64, :u64], [
      chain,
      asset,
      rev,
      buyer,
      price,
      deadline
    ])
  end

  @doc "Documento que o órgão aprova para adicionar um gravame."
  @spec lien_add_doc(String.t(), String.t(), non_neg_integer(), String.t(), String.t()) ::
          binary()
  def lien_add_doc(chain, asset, rev, lien, ref) do
    doc("lien_add", [:string, :string, :u64, :string, :string], [chain, asset, rev, lien, ref])
  end

  @doc "Documento que o órgão aprova para remover um gravame."
  @spec lien_remove_doc(String.t(), String.t(), non_neg_integer(), String.t(), String.t()) ::
          binary()
  def lien_remove_doc(chain, asset, rev, lien, ref) do
    doc("lien_remove", [:string, :string, :u64, :string, :string], [chain, asset, rev, lien, ref])
  end

  defp doc(op, schema, values),
    do: Hash.tagged("brdc/asset/" <> op, Encoding.encode(schema, values))

  # --- cargas (para quem monta transações) -------------------------------------------

  @spec class_payload(String.t(), [binary()], pos_integer(), pos_integer(), [binary()]) ::
          binary()
  def class_payload(id, organ, threshold, window, approvals),
    do:
      Encoding.encode([:string, {:list, {:fixed, 32}}, :u32, :u64, @list_approvals], [
        id,
        organ,
        threshold,
        window,
        approvals
      ])

  @spec register_payload(String.t(), String.t(), binary(), binary(), [binary()]) :: binary()
  def register_payload(class, asset, owner, meta, approvals),
    do:
      Encoding.encode([:string, :string, {:fixed, 32}, :bytes, @list_approvals], [
        class,
        asset,
        owner,
        meta,
        approvals
      ])

  @spec offer_payload(String.t(), binary(), non_neg_integer()) :: binary()
  def offer_payload(asset, buyer, price),
    do: Encoding.encode([:string, {:fixed, 32}, :u64], [asset, buyer, price])

  @spec asset_payload(String.t()) :: binary()
  def asset_payload(asset), do: Encoding.encode([:string], [asset])

  @spec veto_payload(String.t(), [binary()]) :: binary()
  def veto_payload(asset, approvals),
    do: Encoding.encode([:string, @list_approvals], [asset, approvals])

  @spec lien_add_payload(String.t(), String.t(), String.t(), [binary()]) :: binary()
  def lien_add_payload(asset, lien, ref, approvals),
    do:
      Encoding.encode([:string, :string, :string, @list_approvals], [asset, lien, ref, approvals])

  @spec lien_remove_payload(String.t(), String.t(), [binary()]) :: binary()
  def lien_remove_payload(asset, lien, approvals),
    do: Encoding.encode([:string, :string, @list_approvals], [asset, lien, approvals])

  # --- execução -------------------------------------------------------------------------

  @doc "Executa uma transação de bens. O executor já cobrou a taxa e subiu o nonce."
  @spec run(State.t(), <<_::256>>, 5..13, binary()) :: {:ok, State.t()} | {:error, atom()}
  def run(s, _sender, 5, payload) do
    with {:ok, [id, organ, threshold, window, approvals]} <-
           decode(payload, [:string, {:list, {:fixed, 32}}, :u32, :u64, @list_approvals]),
         :ok <- check(id_ok?(id, 32), :bad_id),
         :ok <- check(not Map.has_key?(s.classes, id), :class_exists),
         :ok <- check(organ_ok?(organ, threshold), :bad_class),
         :ok <- check(window in s.params.min_window..s.params.max_window//1, :bad_class),
         :ok <- check(s.params.authorities != [], :no_authority),
         d = class_doc(s.params.chain_id, id, organ, threshold, window),
         :ok <-
           check(
             Approvals.enough?(d, approvals, s.params.authorities, s.params.authority_threshold),
             :not_enough_approvals
           ) do
      class = %{organ: organ, threshold: threshold, veto_window: window}
      {:ok, %{s | classes: Map.put(s.classes, id, class)}}
    end
  end

  def run(s, _sender, 6, payload) do
    with {:ok, [class_id, asset_id, owner, meta, approvals]} <-
           decode(payload, [:string, :string, {:fixed, 32}, :bytes, @list_approvals]),
         {:ok, class} <- fetch(s.classes, class_id, :no_class),
         :ok <- check(id_ok?(asset_id, 64) and byte_size(meta) <= 256, :bad_id),
         :ok <- check(not Map.has_key?(s.assets, asset_id), :asset_exists),
         d = register_doc(s.params.chain_id, class_id, asset_id, owner, meta),
         :ok <- organ_approved(class, d, approvals) do
      asset = %{class: class_id, owner: owner, meta: meta, rev: 0, liens: %{}}
      {:ok, %{s | assets: Map.put(s.assets, asset_id, asset)}}
    end
  end

  def run(s, sender, 7, payload) do
    with {:ok, [asset_id, buyer, price]} <- decode(payload, [:string, {:fixed, 32}, :u64]),
         {:ok, asset} <- fetch(s.assets, asset_id, :no_asset),
         :ok <- check(asset.owner == sender, :not_owner),
         :ok <- check(not Map.has_key?(s.deals, asset_id), :deal_active),
         :ok <- check(map_size(asset.liens) == 0, :has_lien),
         :ok <- check(buyer != sender, :self_deal) do
      deal = %{seller: sender, buyer: buyer, price: price, status: :offered, deadline: nil}
      {:ok, %{s | deals: Map.put(s.deals, asset_id, deal)}}
    end
  end

  def run(s, sender, 8, payload) do
    with {:ok, [asset_id]} <- decode(payload, [:string]),
         {:ok, deal} <- fetch(s.deals, asset_id, :no_deal),
         :ok <- check(deal.buyer == sender, :not_buyer),
         :ok <- check(deal.status == :offered, :bad_status),
         acc = State.account(s, sender),
         :ok <- check(acc.balance >= deal.price, :insufficient_funds) do
      window = s.classes[s.assets[asset_id].class].veto_window
      s1 = State.put_account(s, sender, %{acc | balance: acc.balance - deal.price})
      deal = %{deal | status: :accepted, deadline: s.time + window}
      {:ok, %{s1 | escrow: s1.escrow + deal.price, deals: Map.put(s1.deals, asset_id, deal)}}
    end
  end

  def run(s, sender, 9, payload) do
    with {:ok, [asset_id]} <- decode(payload, [:string]),
         {:ok, deal} <- fetch(s.deals, asset_id, :no_deal),
         :ok <- check(deal.seller == sender, :not_owner),
         :ok <- check(deal.status == :offered, :bad_status) do
      {:ok, %{s | deals: Map.delete(s.deals, asset_id)}}
    end
  end

  def run(s, _sender, 10, payload) do
    with {:ok, [asset_id, approvals]} <- decode(payload, [:string, @list_approvals]),
         {:ok, deal} <- fetch(s.deals, asset_id, :no_deal),
         :ok <- check(deal.status == :accepted, :bad_status),
         :ok <- check(s.time < deal.deadline, :window_closed),
         asset = s.assets[asset_id],
         d =
           veto_doc(s.params.chain_id, asset_id, asset.rev, deal.buyer, deal.price, deal.deadline),
         :ok <- organ_approved(s.classes[asset.class], d, approvals) do
      buyer = State.account(s, deal.buyer)
      s1 = State.put_account(s, deal.buyer, %{buyer | balance: buyer.balance + deal.price})

      {:ok,
       %{
         s1
         | escrow: s1.escrow - deal.price,
           deals: Map.delete(s1.deals, asset_id),
           assets: Map.put(s1.assets, asset_id, %{asset | rev: asset.rev + 1})
       }}
    end
  end

  def run(s, _sender, 11, payload) do
    with {:ok, [asset_id]} <- decode(payload, [:string]),
         {:ok, deal} <- fetch(s.deals, asset_id, :no_deal),
         :ok <- check(deal.status == :accepted, :bad_status),
         :ok <- check(s.time >= deal.deadline, :window_open),
         asset = s.assets[asset_id],
         :ok <- check(map_size(asset.liens) == 0, :has_lien),
         seller = State.account(s, deal.seller),
         :ok <- check(seller.balance + deal.price <= @max_u64, :overflow) do
      s1 = State.put_account(s, deal.seller, %{seller | balance: seller.balance + deal.price})

      {:ok,
       %{
         s1
         | escrow: s1.escrow - deal.price,
           deals: Map.delete(s1.deals, asset_id),
           assets: Map.put(s1.assets, asset_id, %{asset | owner: deal.buyer, rev: asset.rev + 1})
       }}
    end
  end

  def run(s, _sender, 12, payload) do
    with {:ok, [asset_id, lien, ref, approvals]} <-
           decode(payload, [:string, :string, :string, @list_approvals]),
         {:ok, asset} <- fetch(s.assets, asset_id, :no_asset),
         :ok <- check(id_ok?(lien, 32) and byte_size(ref) <= 128, :bad_id),
         :ok <- check(not Map.has_key?(asset.liens, lien), :lien_exists),
         d = lien_add_doc(s.params.chain_id, asset_id, asset.rev, lien, ref),
         :ok <- organ_approved(s.classes[asset.class], d, approvals) do
      asset = %{asset | liens: Map.put(asset.liens, lien, ref), rev: asset.rev + 1}
      {:ok, %{s | assets: Map.put(s.assets, asset_id, asset)}}
    end
  end

  def run(s, _sender, 13, payload) do
    with {:ok, [asset_id, lien, approvals]} <-
           decode(payload, [:string, :string, @list_approvals]),
         {:ok, asset} <- fetch(s.assets, asset_id, :no_asset),
         {:ok, ref} <- fetch(asset.liens, lien, :no_lien),
         d = lien_remove_doc(s.params.chain_id, asset_id, asset.rev, lien, ref),
         :ok <- organ_approved(s.classes[asset.class], d, approvals) do
      asset = %{asset | liens: Map.delete(asset.liens, lien), rev: asset.rev + 1}
      {:ok, %{s | assets: Map.put(s.assets, asset_id, asset)}}
    end
  end

  # --- util ---------------------------------------------------------------------------------

  defp organ_approved(class, doc, approvals) do
    check(Approvals.enough?(doc, approvals, class.organ, class.threshold), :not_enough_approvals)
  end

  defp organ_ok?(organ, threshold) do
    length(organ) in 1..16 and length(Enum.uniq(organ)) == length(organ) and threshold >= 1 and
      threshold <= length(organ)
  end

  defp id_ok?(id, max), do: byte_size(id) in 1..max and String.printable?(id)

  defp fetch(map, key, reason) do
    case Map.fetch(map, key) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, reason}
    end
  end

  defp decode(payload, schema) do
    case Encoding.decode(schema, payload) do
      {:ok, v} -> {:ok, v}
      _ -> {:error, :bad_payload}
    end
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
