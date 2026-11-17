defmodule BrdcLedger.Params do
  @moduledoc """
  Parâmetros da rede, fixados na gênese (ADR-0013 e ADR-0014).

  Valores em **unidades mínimas** (1 BRDC = 1_000_000, ADR-0010). A tabela de taxas padrão
  segue o ADR-0014: transferência 0,001 BRDC + 0,000001 BRDC por byte; mint e burn sem
  taxa mínima. Mudar parâmetros só por mais de 2/3 dos validadores (fase de governança).
  """

  @enforce_keys [:chain_id, :issuers, :threshold]
  defstruct [
    :chain_id,
    :issuers,
    :threshold,
    transfer_base: 1_000,
    per_byte: 1,
    max_block_txs: 1_000,
    max_block_bytes: 1_000_000
  ]

  @type t :: %__MODULE__{
          chain_id: String.t(),
          issuers: [<<_::256>>],
          threshold: pos_integer(),
          transfer_base: non_neg_integer(),
          per_byte: non_neg_integer(),
          max_block_txs: pos_integer(),
          max_block_bytes: pos_integer()
        }

  @doc "1 BRDC em unidades mínimas."
  @spec unit() :: 1_000_000
  def unit, do: 1_000_000

  @doc "Cria os parâmetros conferindo `1 <= threshold <= length(issuers)` e emissores distintos."
  @spec new(keyword()) :: {:ok, t()} | {:error, :bad_issuers | :bad_threshold}
  def new(opts) do
    p = struct!(__MODULE__, opts)

    cond do
      p.issuers == [] or length(Enum.uniq(p.issuers)) != length(p.issuers) ->
        {:error, :bad_issuers}

      p.threshold < 1 or p.threshold > length(p.issuers) ->
        {:error, :bad_threshold}

      true ->
        {:ok, p}
    end
  end
end
