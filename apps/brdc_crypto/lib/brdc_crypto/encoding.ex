defmodule BrdcCrypto.Encoding do
  @moduledoc """
  Codificação determinística própria (ADR-0011), Fase 1.

  Cada campo é escrito em ordem fixa, sem separadores nem nomes:

  | tipo        | bytes                                   |
  |-------------|------------------------------------------|
  | `:u8`       | 1                                        |
  | `:u32`      | 4, big-endian                            |
  | `:u64`      | 8, big-endian                            |
  | `:bytes`    | tamanho (4 bytes) + conteúdo             |
  | `:string`   | igual a `:bytes`, deve ser UTF-8 válido  |
  | `{:fixed, n}` | exatamente `n` bytes, sem prefixo      |
  | `{:list, t}`| quantidade (4 bytes) + cada item         |

  O esquema (a lista de tipos) é conhecido por quem lê; a decodificação recusa
  sobras, faltas e UTF-8 inválido. Nunca se usa `:erlang.term_to_binary`.
  """

  @type type :: :u8 | :u32 | :u64 | :bytes | :string | {:fixed, pos_integer()} | {:list, type()}

  @doc "Codifica `values` segundo `schema` (mesmo tamanho)."
  @spec encode([type()], [term()]) :: binary()
  def encode(schema, values) when length(schema) == length(values) do
    schema |> Enum.zip(values) |> Enum.map(fn {t, v} -> enc(t, v) end) |> IO.iodata_to_binary()
  end

  @doc "Decodifica; recusa bytes sobrando ou faltando."
  @spec decode([type()], binary()) :: {:ok, [term()]} | {:error, :malformed}
  def decode(schema, bin) when is_binary(bin) do
    case dec_all(schema, bin, []) do
      {:ok, values, <<>>} -> {:ok, values}
      _ -> {:error, :malformed}
    end
  end

  defp enc(:u8, v) when v in 0..0xFF, do: <<v::8>>
  defp enc(:u32, v) when v in 0..0xFFFFFFFF, do: <<v::32>>
  defp enc(:u64, v) when v in 0..0xFFFFFFFFFFFFFFFF, do: <<v::64>>
  defp enc(:bytes, v) when is_binary(v), do: <<byte_size(v)::32, v::binary>>

  defp enc(:string, v) when is_binary(v) do
    if String.valid?(v), do: enc(:bytes, v), else: raise(ArgumentError, "invalid UTF-8")
  end

  defp enc({:fixed, n}, v) when is_binary(v) and byte_size(v) == n, do: v
  defp enc({:list, t}, vs) when is_list(vs), do: [<<length(vs)::32>> | Enum.map(vs, &enc(t, &1))]

  defp dec_all([], rest, acc), do: {:ok, Enum.reverse(acc), rest}

  defp dec_all([t | ts], bin, acc) do
    with {:ok, v, rest} <- dec(t, bin), do: dec_all(ts, rest, [v | acc])
  end

  defp dec(:u8, <<v::8, r::binary>>), do: {:ok, v, r}
  defp dec(:u32, <<v::32, r::binary>>), do: {:ok, v, r}
  defp dec(:u64, <<v::64, r::binary>>), do: {:ok, v, r}
  defp dec(:bytes, <<n::32, v::binary-size(n), r::binary>>), do: {:ok, v, r}

  defp dec(:string, bin) do
    with {:ok, v, r} <- dec(:bytes, bin), true <- String.valid?(v), do: {:ok, v, r}
  end

  defp dec({:fixed, n}, bin) when byte_size(bin) >= n do
    <<v::binary-size(^n), r::binary>> = bin
    {:ok, v, r}
  end

  defp dec({:list, t}, <<n::32, r::binary>>), do: dec_list(t, n, r, [])
  defp dec(_, _), do: :error

  defp dec_list(_t, 0, r, acc), do: {:ok, Enum.reverse(acc), r}

  defp dec_list(t, n, bin, acc) do
    with {:ok, v, r} <- dec(t, bin), do: dec_list(t, n - 1, r, [v | acc])
  end
end
