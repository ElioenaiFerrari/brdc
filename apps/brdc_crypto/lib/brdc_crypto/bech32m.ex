defmodule BrdcCrypto.Bech32m do
  @moduledoc """
  Bech32m (BIP-350), Fase 1: texto com prefixo legível (HRP) e checksum que
  detecta erro de digitação. Usado nos endereços `brdc1…` (ADR-0010).
  """
  import Bitwise

  @charset ~c"qpzry9x8gf2tvdw0s3jn54khce6mua7l"
  @const 0x2BC830A3
  @gen [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]

  @doc "Codifica `data` (bytes) com o prefixo `hrp`."
  @spec encode(String.t(), binary()) :: String.t()
  def encode(hrp, data) when is_binary(hrp) and is_binary(data) do
    five = to_five(data)
    checksum = create_checksum(hrp, five)
    hrp <> "1" <> to_string(for v <- five ++ checksum, do: Enum.at(@charset, v))
  end

  @doc "Decodifica e confere o checksum. Devolve `{:ok, hrp, bytes}` ou `{:error, motivo}`."
  @spec decode(String.t()) :: {:ok, String.t(), binary()} | {:error, atom()}
  def decode(str) when is_binary(str) do
    with :ok <- check_case(str),
         {:ok, hrp, rest} <- split(String.downcase(str)),
         {:ok, values} <- to_values(rest),
         :ok <- check_length(values),
         :ok <- check_checksum(hrp, values) do
      from_five(Enum.drop(values, -6)) |> wrap(hrp)
    end
  end

  defp wrap({:ok, bytes}, hrp), do: {:ok, hrp, bytes}
  defp wrap(err, _hrp), do: err

  defp check_length(values),
    do: if(length(values) >= 6, do: :ok, else: {:error, :too_short})

  defp check_checksum(hrp, values),
    do: if(polymod(hrp_expand(hrp) ++ values) == @const, do: :ok, else: {:error, :bad_checksum})

  defp check_case(s) do
    if s == String.downcase(s) or s == String.upcase(s), do: :ok, else: {:error, :mixed_case}
  end

  defp split(s) do
    case :binary.matches(s, "1") do
      [] -> {:error, :no_separator}
      ms -> split_at(s, ms |> List.last() |> elem(0))
    end
  end

  defp split_at(_s, 0), do: {:error, :empty_hrp}

  defp split_at(s, pos),
    do: {:ok, binary_part(s, 0, pos), binary_part(s, pos + 1, byte_size(s) - pos - 1)}

  defp to_values(rest) do
    rest
    |> :binary.bin_to_list()
    |> Enum.reduce_while({:ok, []}, fn c, {:ok, acc} ->
      case Enum.find_index(@charset, &(&1 == c)) do
        nil -> {:halt, {:error, :invalid_char}}
        i -> {:cont, {:ok, [i | acc]}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp create_checksum(hrp, five) do
    pm = bxor(polymod(hrp_expand(hrp) ++ five ++ [0, 0, 0, 0, 0, 0]), @const)
    for i <- 0..5, do: pm >>> (5 * (5 - i)) &&& 31
  end

  defp hrp_expand(hrp) do
    l = :binary.bin_to_list(hrp)
    Enum.map(l, &(&1 >>> 5)) ++ [0] ++ Enum.map(l, &(&1 &&& 31))
  end

  defp polymod(values), do: Enum.reduce(values, 1, &polymod_step/2)

  defp polymod_step(v, chk) do
    top = chk >>> 25
    chk = bxor((chk &&& 0x1FFFFFF) <<< 5, v)

    @gen
    |> Enum.with_index()
    |> Enum.reduce(chk, &apply_gen(&1, &2, top))
  end

  defp apply_gen({g, i}, c, top), do: if((top >>> i &&& 1) == 1, do: bxor(c, g), else: c)

  # bytes -> grupos de 5 bits (com preenchimento de zeros)
  defp to_five(data) do
    for(<<b::1 <- data>>, do: b)
    |> Enum.chunk_every(5, 5, List.duplicate(0, 4))
    |> Enum.map(&Enum.reduce(&1, 0, fn b, a -> a * 2 + b end))
  end

  # grupos de 5 bits -> bytes; o preenchimento deve ter menos de 5 bits e ser zero
  defp from_five(values) do
    bits = for v <- values, i <- 4..0//-1, do: v >>> i &&& 1
    pad = rem(length(bits), 8)
    {body, tail} = Enum.split(bits, length(bits) - pad)

    if pad > 4 or Enum.any?(tail, &(&1 != 0)) do
      {:error, :bad_padding}
    else
      bytes =
        for chunk <- Enum.chunk_every(body, 8), into: <<>> do
          <<Enum.reduce(chunk, 0, &(&2 * 2 + &1))>>
        end

      {:ok, bytes}
    end
  end
end
