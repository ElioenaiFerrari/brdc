defmodule BrdcNode.Proposals do
  @moduledoc """
  Propostas de assinatura coletiva (Fase 6/7, ADR-0024): um membro de um órgão propõe uma ação, os outros
  assinam, e com M aprovações qualquer um monta e envia a transação.

  Tipos (`kind`): `:credential_issue` · `:asset_register` · `:asset_veto` · `:lien_add` · `:lien_remove`.

  **Puro**: `(armazém, estado do ledger, …) → armazém'`. O nó **não confia no que recebe**: a proposta traz só
  os **campos**; o documento a assinar e o órgão competente são **recalculados aqui** do estado do ledger
  (nas ações sobre bens, a revisão do bem, o comprador, o preço e o prazo vêm do estado, nunca da proposta), e
  cada aprovação é conferida contra o órgão, com chaves distintas. Nada nelas é segredo (assinaturas sobre um
  documento público).

  Limites: no máximo #{200} propostas; uma proposta aberta por alvo (credencial, bem ou gravame); a proposta
  some quando deixa de valer (já emitida, já registrada, negociação encerrada, revisão do bem mudou).
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.{Approvals, Assets, Credentials, State}

  @max 200

  @specs %{
    credential_issue:
      {1, [:type, :id, :subject, :data, :ref], [:string, :string, {:fixed, 32}, :bytes, :string]},
    asset_register:
      {2, [:class, :asset, :owner, :meta], [:string, :string, {:fixed, 32}, :bytes]},
    asset_veto: {3, [:asset], [:string]},
    lien_add: {4, [:asset, :lien, :ref], [:string, :string, :string]},
    lien_remove: {5, [:asset, :lien], [:string, :string]}
  }

  @type kind :: :credential_issue | :asset_register | :asset_veto | :lien_add | :lien_remove
  @type fields :: map()
  @type proposal :: %{id: <<_::256>>, kind: kind(), fields: fields(), approvals: [binary()]}
  @type store :: %{<<_::256>> => proposal()}

  @spec new() :: store()
  def new, do: %{}

  @doc "Os tipos de proposta."
  @spec kinds() :: [kind()]
  def kinds, do: Map.keys(@specs)

  @doc "Número do tipo na porta pública."
  @spec kind_number(kind()) :: pos_integer()
  def kind_number(kind), do: @specs |> Map.fetch!(kind) |> elem(0)

  @doc "Tipo a partir do número da porta pública."
  @spec kind_from_number(integer()) :: {:ok, kind()} | :error
  def kind_from_number(n) do
    case Enum.find(@specs, fn {_k, {num, _, _}} -> num == n end) do
      {kind, _} -> {:ok, kind}
      nil -> :error
    end
  end

  @doc "Codifica os campos do tipo (ordem fixa, o mesmo esquema da porta pública)."
  @spec encode_fields(kind(), fields()) :: binary()
  def encode_fields(kind, f) do
    {_, keys, schema} = Map.fetch!(@specs, kind)
    Encoding.encode(schema, Enum.map(keys, &Map.fetch!(f, &1)))
  end

  @doc "Decodifica os campos do tipo."
  @spec decode_fields(kind(), binary()) :: {:ok, fields()} | {:error, :malformed}
  def decode_fields(kind, bin) do
    {_, keys, schema} = Map.fetch!(@specs, kind)

    case Encoding.decode(schema, bin) do
      {:ok, values} -> {:ok, keys |> Enum.zip(values) |> Map.new()}
      _ -> {:error, :malformed}
    end
  end

  @doc "Identificador da proposta: hash do tipo e dos campos (a mesma proposta tem sempre o mesmo id)."
  @spec id_of(kind(), fields()) :: <<_::256>>
  def id_of(kind, f),
    do: Hash.tagged("brdc/proposal/" <> Atom.to_string(kind), encode_fields(kind, f))

  @doc "Atalho para emissão de credencial."
  @spec id_of(fields()) :: <<_::256>>
  def id_of(f), do: id_of(:credential_issue, f)

  @doc "Documento que os membros assinam (recalculado do estado, nunca recebido pronto)."
  @spec doc(State.t(), kind(), fields()) :: {:ok, binary()} | {:error, atom()}
  def doc(%State{} = state, kind, f) do
    with {:ok, r} <- resolve(state, kind, f), do: {:ok, r.doc}
  end

  @doc "Registra uma proposta. Idempotente: a mesma proposta devolve o mesmo id."
  @spec put(store(), State.t(), kind(), fields()) :: {:ok, store(), <<_::256>>} | {:error, atom()}
  def put(store, %State{} = state, kind, f) when is_map_key(@specs, kind) do
    id = id_of(kind, f)

    cond do
      Map.has_key?(store, id) -> with({:ok, _} <- resolve(state, kind, f), do: {:ok, store, id})
      map_size(store) >= @max -> {:error, :too_many_proposals}
      true -> add(store, state, kind, f, id)
    end
  end

  def put(_store, _state, _kind, _f), do: {:error, :bad_kind}

  @doc "Atalho para emissão de credencial."
  @spec put(store(), State.t(), fields()) :: {:ok, store(), <<_::256>>} | {:error, atom()}
  def put(store, state, f), do: put(store, state, :credential_issue, f)

  defp add(store, state, kind, f, id) do
    with {:ok, r} <- resolve(state, kind, f),
         :ok <- no_open_proposal_for(store, state, r.key) do
      {:ok, Map.put(store, id, %{id: id, kind: kind, fields: f, approvals: []}), id}
    end
  end

  defp no_open_proposal_for(store, state, key) do
    open? =
      Enum.any?(store, fn {_, p} ->
        match?({:ok, %{key: ^key}}, resolve(state, p.kind, p.fields))
      end)

    if open?, do: {:error, :proposal_exists}, else: :ok
  end

  @doc "Acrescenta a aprovação de um membro do órgão (`chave ‖ assinatura`, 96 bytes). Duplicada não conta."
  @spec approve(store(), State.t(), <<_::256>>, binary()) ::
          {:ok, store(), non_neg_integer()} | {:error, atom()}
  def approve(store, %State{} = state, id, approval) when is_binary(approval) do
    with {:ok, p} <- store |> Map.fetch(id) |> ok_or(:no_proposal),
         {:ok, r} <- resolve(state, p.kind, p.fields),
         [signer] <- Approvals.signers(r.doc, [approval], r.organ) do
      if Enum.any?(p.approvals, &(binary_part(&1, 0, 32) == signer)) do
        {:ok, store, length(p.approvals)}
      else
        p = %{p | approvals: p.approvals ++ [approval]}
        {:ok, Map.put(store, id, p), length(p.approvals)}
      end
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_approval}
    end
  end

  @doc "Propostas dos órgãos de que a chave `pub` faz parte, com o limite (M)."
  @spec list_for(store(), State.t(), <<_::256>>) :: [map()]
  def list_for(store, %State{} = state, pub) do
    for {_, p} <- store,
        {:ok, r} <- [resolve(state, p.kind, p.fields)],
        pub in r.organ do
      Map.put(p, :threshold, r.threshold)
    end
    |> Enum.sort_by(& &1.id)
  end

  @doc "Descarta propostas que deixaram de valer."
  @spec prune(store(), State.t()) :: store()
  def prune(store, %State{} = state) do
    store
    |> Enum.filter(fn {_, p} -> match?({:ok, _}, resolve(state, p.kind, p.fields)) end)
    |> Map.new()
  end

  # --- resolução: órgão, limite, documento e chave de conflito, tudo do estado do ledger ----------------

  defp resolve(s, :credential_issue, f) do
    with {:ok, type} <- Credentials.check_issue(s, f.type, f.id, f.subject, f.data, f.ref) do
      doc = Credentials.issue_doc(s.params.chain_id, f.type, f.id, f.subject, f.data, f.ref)
      {:ok, %{organ: type.organ, threshold: type.threshold, doc: doc, key: {:issue, f.id}}}
    end
  end

  defp resolve(s, :asset_register, f) do
    with {:ok, class} <- fetch(s.classes, f.class, :no_class),
         :ok <- check(id_ok?(f.asset, 64) and byte_size(f.meta) <= 256, :bad_id),
         :ok <- check(not Map.has_key?(s.assets, f.asset), :asset_exists) do
      doc = Assets.register_doc(s.params.chain_id, f.class, f.asset, f.owner, f.meta)

      {:ok,
       %{organ: class.organ, threshold: class.threshold, doc: doc, key: {:register, f.asset}}}
    end
  end

  defp resolve(s, :asset_veto, f) do
    with {:ok, asset} <- fetch(s.assets, f.asset, :no_asset),
         {:ok, deal} <- fetch(s.deals, f.asset, :no_deal),
         :ok <- check(deal.status == :accepted, :bad_status),
         :ok <- check(s.time < deal.deadline, :window_closed) do
      class = Map.fetch!(s.classes, asset.class)

      doc =
        Assets.veto_doc(
          s.params.chain_id,
          f.asset,
          asset.rev,
          deal.buyer,
          deal.price,
          deal.deadline
        )

      {:ok, %{organ: class.organ, threshold: class.threshold, doc: doc, key: {:veto, f.asset}}}
    end
  end

  defp resolve(s, :lien_add, f) do
    with {:ok, asset} <- fetch(s.assets, f.asset, :no_asset),
         :ok <- check(id_ok?(f.lien, 32) and byte_size(f.ref) <= 128, :bad_id),
         :ok <- check(not Map.has_key?(asset.liens, f.lien), :lien_exists) do
      class = Map.fetch!(s.classes, asset.class)
      doc = Assets.lien_add_doc(s.params.chain_id, f.asset, asset.rev, f.lien, f.ref)

      {:ok,
       %{
         organ: class.organ,
         threshold: class.threshold,
         doc: doc,
         key: {:lien_add, f.asset, f.lien}
       }}
    end
  end

  defp resolve(s, :lien_remove, f) do
    with {:ok, asset} <- fetch(s.assets, f.asset, :no_asset),
         {:ok, ref} <- fetch(asset.liens, f.lien, :no_lien) do
      class = Map.fetch!(s.classes, asset.class)
      doc = Assets.lien_remove_doc(s.params.chain_id, f.asset, asset.rev, f.lien, ref)

      {:ok,
       %{
         organ: class.organ,
         threshold: class.threshold,
         doc: doc,
         key: {:lien_remove, f.asset, f.lien}
       }}
    end
  end

  defp id_ok?(id, max), do: byte_size(id) in 1..max and String.printable?(id)

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp fetch(map, key, reason), do: map |> Map.fetch(key) |> ok_or(reason)

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(:error, reason), do: {:error, reason}
end
