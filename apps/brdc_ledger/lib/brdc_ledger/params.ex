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
    max_block_bytes: 1_000_000,
    contest_window: 86_400,
    veto_window: 172_800,
    min_window: 60,
    max_window: 31_536_000,
    authorities: [],
    authority_threshold: 1,
    asset_register_fee: 50_000,
    asset_step_fee: 20_000
  ]

  @type t :: %__MODULE__{
          chain_id: String.t(),
          issuers: [<<_::256>>],
          threshold: pos_integer(),
          transfer_base: non_neg_integer(),
          per_byte: non_neg_integer(),
          max_block_txs: pos_integer(),
          max_block_bytes: pos_integer(),
          contest_window: pos_integer(),
          veto_window: pos_integer(),
          min_window: pos_integer(),
          max_window: pos_integer(),
          authorities: [<<_::256>>],
          authority_threshold: pos_integer(),
          asset_register_fee: non_neg_integer(),
          asset_step_fee: non_neg_integer()
        }

  @doc "1 BRDC em unidades mínimas."
  @spec unit() :: 1_000_000
  def unit, do: 1_000_000

  @doc "Cria os parâmetros conferindo `1 <= threshold <= length(issuers)` e emissores distintos."
  @spec new(keyword()) ::
          {:ok, t()} | {:error, :bad_issuers | :bad_threshold | :bad_windows | :bad_authorities}
  def new(opts) do
    p = struct!(__MODULE__, opts)

    cond do
      p.issuers == [] or length(Enum.uniq(p.issuers)) != length(p.issuers) ->
        {:error, :bad_issuers}

      p.threshold < 1 or p.threshold > length(p.issuers) ->
        {:error, :bad_threshold}

      not valid_windows?(p) ->
        {:error, :bad_windows}

      not valid_authorities?(p) ->
        {:error, :bad_authorities}

      true ->
        {:ok, p}
    end
  end

  # autoridades raiz (criam classes de bens e tipos de credencial): distintas, e o limite cabe no conjunto
  defp valid_authorities?(%{authorities: []}), do: true

  defp valid_authorities?(p) do
    length(Enum.uniq(p.authorities)) == length(p.authorities) and
      p.authority_threshold >= 1 and p.authority_threshold <= length(p.authorities)
  end

  # as janelas (segundos, ADR-0016) ficam entre o mínimo e o máximo permitidos
  defp valid_windows?(p) do
    p.min_window >= 1 and p.min_window <= p.max_window and
      p.contest_window in p.min_window..p.max_window//1 and
      p.veto_window in p.min_window..p.max_window//1
  end
end
