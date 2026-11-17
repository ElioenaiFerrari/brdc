defmodule BrdcCrypto.Slip10 do
  @moduledoc """
  SLIP-0010 para Ed25519, Fase 1 (ADR-0005).

  Deriva chaves a partir da semente do BIP-39. Em Ed25519 só existe derivação
  **endurecida** (cada índice vira `index + 2^31`). Caminho padrão BRDC:
  `m/44'/<coin>'/<conta>'/0'/<índice>'` (ver docs/concepts/03).
  """
  import Bitwise

  @hardened 0x80000000

  @type node_key :: %{key: <<_::256>>, chain_code: <<_::256>>}

  @doc "Nó mestre: HMAC-SHA512(\"ed25519 seed\", seed)."
  @spec master(binary()) :: node_key()
  def master(seed) when is_binary(seed) do
    <<key::binary-32, chain::binary-32>> = :crypto.mac(:hmac, :sha512, "ed25519 seed", seed)
    %{key: key, chain_code: chain}
  end

  @doc "Deriva um filho endurecido. `index` é o número sem o bit de endurecimento."
  @spec child(node_key(), non_neg_integer()) :: node_key()
  def child(%{key: key, chain_code: chain}, index) when index >= 0 and index < @hardened do
    data = <<0, key::binary, index ||| @hardened::32>>
    <<k::binary-32, c::binary-32>> = :crypto.mac(:hmac, :sha512, chain, data)
    %{key: k, chain_code: c}
  end

  @doc """
  Deriva por caminho, ex.: `\"m/44'/0'/0'\"`. Todos os índices devem ser endurecidos (`'`).
  Devolve `{:ok, nó}` ou `{:error, :bad_path}`.
  """
  @spec derive(binary(), String.t()) :: {:ok, node_key()} | {:error, :bad_path}
  def derive(seed, path) when is_binary(seed) and is_binary(path) do
    with {:ok, indexes} <- parse(path) do
      {:ok, Enum.reduce(indexes, master(seed), &child(&2, &1))}
    end
  end

  defp parse("m"), do: {:ok, []}

  defp parse("m/" <> rest) do
    rest
    |> String.split("/")
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_index(part) do
        {:ok, n} -> {:cont, {:ok, [n | acc]}}
        :error -> {:halt, {:error, :bad_path}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp parse(_), do: {:error, :bad_path}

  # só índices endurecidos, ex.: "44'"
  defp parse_index(part) do
    with true <- String.ends_with?(part, "'"),
         {n, ""} <- Integer.parse(String.trim_trailing(part, "'")),
         true <- n >= 0 and n < @hardened do
      {:ok, n}
    else
      _ -> :error
    end
  end
end
