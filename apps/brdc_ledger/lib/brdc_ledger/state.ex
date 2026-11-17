defmodule BrdcLedger.State do
  @moduledoc """
  Estado do livro-razão (Fase 2): contas (saldo + nonce), oferta emitida e queimada e
  referências de emissão já usadas. Estrutura **pura**: sem processos, sem relógio, sem acaso.

  A raiz de estado (`root/1`) é um resumo de tudo isso: dois nós com o mesmo estado têm a
  mesma raiz. Por ora é uma árvore de Merkle simples sobre as contas ordenadas; a árvore
  esparsa e o armazenamento em disco são o ADR-0012 (ainda proposto).
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.Params

  @enforce_keys [:params]
  defstruct params: nil,
            accounts: %{},
            minted: 0,
            burned: 0,
            refs: MapSet.new(),
            attestation: nil,
            classes: %{},
            assets: %{},
            deals: %{},
            escrow: 0,
            height: 0,
            time: 0,
            last_hash: nil

  @type account :: %{balance: non_neg_integer(), nonce: non_neg_integer()}
  @type t :: %__MODULE__{
          params: Params.t(),
          accounts: %{<<_::256>> => account()},
          minted: non_neg_integer(),
          burned: non_neg_integer(),
          refs: MapSet.t({atom(), String.t()}),
          classes: %{String.t() => map()},
          assets: %{String.t() => map()},
          deals: %{String.t() => map()},
          escrow: non_neg_integer(),
          attestation: nil | %{seq: pos_integer(), reserve: non_neg_integer(), ref: String.t()},
          height: non_neg_integer(),
          time: non_neg_integer(),
          last_hash: nil | <<_::256>>
        }

  @max_u64 0xFFFFFFFFFFFFFFFF
  def max_u64, do: @max_u64

  @spec new(Params.t()) :: t()
  def new(%Params{} = params), do: %__MODULE__{params: params}

  @spec account(t(), <<_::256>>) :: account()
  def account(%__MODULE__{accounts: a}, addr), do: Map.get(a, addr, %{balance: 0, nonce: 0})

  @spec balance(t(), <<_::256>>) :: non_neg_integer()
  def balance(state, addr), do: account(state, addr).balance

  @doc "Soma de todos os saldos."
  @spec total_balances(t()) :: non_neg_integer()
  def total_balances(%__MODULE__{accounts: a}),
    do: a |> Map.values() |> Enum.reduce(0, &(&1.balance + &2))

  @doc "Saldos + escrow: tudo o que está em circulação (igual a emitido − queimado)."
  @spec total_held(t()) :: non_neg_integer()
  def total_held(%__MODULE__{escrow: e} = s), do: total_balances(s) + e

  @doc "Oferta em circulação = emitido − queimado."
  @spec supply(t()) :: non_neg_integer()
  def supply(%__MODULE__{minted: m, burned: b}), do: m - b

  @doc """
  Cobertura informada pelos emissores: compara o último atestado de reserva com a oferta.
  É **só informação** (a chain não prova a reserva real e não congela nada, ADR-0009).
  """
  @spec coverage(t()) :: :none | {:covered | :under, integer()}
  def coverage(%__MODULE__{attestation: nil}), do: :none

  def coverage(%__MODULE__{attestation: %{reserve: r}} = s) do
    margin = r - supply(s)
    if margin >= 0, do: {:covered, margin}, else: {:under, margin}
  end

  @doc "Grava uma conta."
  @spec put_account(t(), <<_::256>>, account()) :: t()
  def put_account(%__MODULE__{} = s, addr, acc),
    do: %{s | accounts: Map.put(s.accounts, addr, acc)}

  @doc "Raiz de estado (32 bytes)."
  @spec root(t()) :: <<_::256>>
  def root(%__MODULE__{} = s) do
    leaves =
      s.accounts
      |> Enum.sort()
      |> Enum.map(fn {addr, a} ->
        Hash.tagged(
          "brdc/state/account",
          Encoding.encode([{:fixed, 32}, :u64, :u64], [addr, a.balance, a.nonce])
        )
      end)

    ref_leaves =
      s.refs
      |> Enum.sort()
      |> Enum.map(fn {kind, ref} ->
        Hash.tagged(
          "brdc/state/ref",
          Encoding.encode([:string, :string], [Atom.to_string(kind), ref])
        )
      end)

    Hash.tagged(
      "brdc/state",
      Encoding.encode(
        [
          :u64,
          :u64,
          :u64,
          {:fixed, 32},
          :u64,
          {:fixed, 32},
          :u64,
          :u64,
          :string,
          :u64,
          {:fixed, 32},
          {:fixed, 32},
          {:fixed, 32},
          :u64
        ],
        [
          s.minted,
          s.burned,
          length(leaves),
          merkle(leaves),
          length(ref_leaves),
          merkle(ref_leaves)
        ] ++
          attestation_fields(s.attestation) ++
          [
            s.time,
            merkle(class_leaves(s)),
            merkle(asset_leaves(s)),
            merkle(deal_leaves(s)),
            s.escrow
          ]
      )
    )
  end

  defp class_leaves(s) do
    for {id, c} <- Enum.sort(s.classes) do
      Hash.tagged(
        "brdc/state/class",
        Encoding.encode(
          [:string, {:list, {:fixed, 32}}, :u32, :u64],
          [id, c.organ, c.threshold, c.veto_window]
        )
      )
    end
  end

  defp asset_leaves(s) do
    for {id, a} <- Enum.sort(s.assets) do
      liens =
        for {lid, ref} <- Enum.sort(a.liens), do: Encoding.encode([:string, :string], [lid, ref])

      Hash.tagged(
        "brdc/state/asset",
        Encoding.encode(
          [:string, :string, {:fixed, 32}, :bytes, :u64, {:list, :bytes}],
          [id, a.class, a.owner, a.meta, a.rev, liens]
        )
      )
    end
  end

  defp deal_leaves(s) do
    for {id, d} <- Enum.sort(s.deals) do
      Hash.tagged(
        "brdc/state/deal",
        Encoding.encode(
          [:string, {:fixed, 32}, {:fixed, 32}, :u64, :u8, :u64],
          [
            id,
            d.seller,
            d.buyer,
            d.price,
            if(d.status == :offered, do: 0, else: 1),
            d.deadline || 0
          ]
        )
      )
    end
  end

  defp attestation_fields(nil), do: [0, 0, ""]
  defp attestation_fields(%{seq: q, reserve: r, ref: f}), do: [q, r, f]

  defp merkle([]), do: Hash.tagged("brdc/merkle/empty", "")
  defp merkle(leaves), do: leaves |> Enum.map(&Hash.tagged("brdc/merkle/leaf", &1)) |> fold()

  defp fold([one]), do: one
  defp fold(level), do: level |> Enum.chunk_every(2) |> Enum.map(&pair/1) |> fold()

  defp pair([a, b]), do: Hash.tagged("brdc/merkle/node", a <> b)
  defp pair([a]), do: a
end
