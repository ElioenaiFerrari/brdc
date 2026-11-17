defmodule BrdcP2p.Frame do
  @moduledoc """
  Quadro da rede (ADR-0015): `tamanho (4 bytes, big-endian) ‖ conteúdo`. O tamanho é conferido
  **antes** de se reservar ou ler o conteúdo, então um par não consegue forçar uma alocação
  gigante anunciando um tamanho absurdo.
  """

  @default_max 1_048_576

  @spec default_max() :: pos_integer()
  def default_max, do: @default_max

  @doc "Monta o quadro; recusa conteúdo acima do limite."
  @spec encode(binary(), pos_integer()) :: {:ok, iodata()} | {:error, :too_large}
  def encode(payload, max \\ @default_max) when is_binary(payload) do
    if byte_size(payload) <= max,
      do: {:ok, [<<byte_size(payload)::32>>, payload]},
      else: {:error, :too_large}
  end

  @doc "Confere o cabeçalho de 4 bytes e devolve o tamanho do conteúdo."
  @spec parse_header(binary(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, :too_large | :malformed}
  def parse_header(<<n::32>>, max) when n <= max, do: {:ok, n}
  def parse_header(<<_::32>>, _max), do: {:error, :too_large}
  def parse_header(_, _), do: {:error, :malformed}

  @doc "Separa quadros de um buffer. Devolve `{quadros, resto}` ou erro se algum passar do limite."
  @spec split(binary(), pos_integer()) :: {:ok, [binary()], binary()} | {:error, :too_large}
  def split(buffer, max \\ @default_max), do: split(buffer, max, [])

  defp split(<<n::32, _::binary>>, max, _acc) when n > max, do: {:error, :too_large}

  defp split(<<n::32, payload::binary-size(n), rest::binary>>, max, acc),
    do: split(rest, max, [payload | acc])

  defp split(rest, _max, acc), do: {:ok, Enum.reverse(acc), rest}
end
