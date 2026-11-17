defmodule BrdcP2p.Rate do
  @moduledoc """
  Balde de fichas (token bucket) para limitar a taxa de mensagens por sessão (Fase 4).
  Puro: o tempo entra como argumento (ms). `rate` fichas por segundo, até `burst` acumuladas.
  """
  defstruct [:rate, :burst, :tokens, :at]

  @type t :: %__MODULE__{rate: number(), burst: pos_integer(), tokens: float(), at: integer()}

  @spec new(number(), pos_integer(), integer()) :: t()
  def new(rate, burst, now),
    do: %__MODULE__{rate: rate, burst: burst, tokens: burst * 1.0, at: now}

  @doc "Tenta gastar `n` fichas. `{:error, :limited}` se não houver (o balde não muda)."
  @spec take(t(), integer(), pos_integer()) :: {:ok, t()} | {:error, :limited}
  def take(%__MODULE__{} = b, now, n \\ 1) do
    refilled = min(b.burst * 1.0, b.tokens + max(now - b.at, 0) * b.rate / 1000)

    if refilled >= n do
      {:ok, %{b | tokens: refilled - n, at: now}}
    else
      {:error, :limited}
    end
  end
end
