defmodule BrdcCrypto.Bip39 do
  @moduledoc """
  BIP-39, Fase 1 (ADR-0005): frase mnemônica e semente, com **passphrase**
  opcional (a "25ª palavra").

  - `entropy -> mnemonic`: entropia de 16/20/24/28/32 bytes + checksum (primeiros
    `ENT/32` bits de SHA-256) viram grupos de 11 bits que indexam a lista de 2048 palavras.
  - `mnemonic -> seed`: `PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" <> passphrase, 2048, 64)`.

  A passphrase **não** é validada: qualquer passphrase gera uma carteira válida,
  e uma passphrase diferente gera uma carteira totalmente diferente.
  """

  @wordlist_path Path.expand("../../priv/bip39_english.txt", __DIR__)
  @external_resource @wordlist_path
  @words @wordlist_path |> File.read!() |> String.split("\n", trim: true)

  @index @words |> Enum.with_index() |> Map.new()

  @doc "Lista de 2048 palavras."
  @spec wordlist() :: [String.t()]
  def wordlist, do: @words

  @doc "Gera uma frase nova (`strength` em bits: 128, 160, 192, 224 ou 256; padrão 256 = 24 palavras)."
  @spec generate(128 | 160 | 192 | 224 | 256) :: String.t()
  def generate(strength \\ 256) when strength in [128, 160, 192, 224, 256] do
    strength |> div(8) |> :crypto.strong_rand_bytes() |> from_entropy()
  end

  @doc "Entropia (16/20/24/28/32 bytes) -> frase."
  @spec from_entropy(binary()) :: String.t()
  def from_entropy(entropy) when byte_size(entropy) in [16, 20, 24, 28, 32] do
    ent_bits = bit_size(entropy)
    cs_bits = div(ent_bits, 32)
    <<cs::size(^cs_bits), _::bitstring>> = :crypto.hash(:sha256, entropy)
    all = <<entropy::bitstring, cs::size(cs_bits)>>

    for(<<i::11 <- all>>, do: Enum.at(@words, i))
    |> Enum.join(" ")
  end

  @doc "Confere o tamanho, as palavras e o checksum. Devolve `{:ok, entropia}` ou `{:error, motivo}`."
  @spec to_entropy(String.t()) ::
          {:ok, binary()} | {:error, :bad_length | :unknown_word | :bad_checksum}
  def to_entropy(mnemonic) when is_binary(mnemonic) do
    words = String.split(normalize(mnemonic), " ", trim: true)

    with true <- length(words) in [12, 15, 18, 21, 24] or {:error, :bad_length},
         {:ok, idxs} <- indexes(words) do
      all = for i <- idxs, into: <<>>, do: <<i::11>>
      total = bit_size(all)
      cs_bits = div(total, 33)
      ent_bits = total - cs_bits
      <<entropy::bitstring-size(^ent_bits), cs::size(^cs_bits)>> = all
      <<expected::size(^cs_bits), _::bitstring>> = :crypto.hash(:sha256, entropy)

      if cs == expected, do: {:ok, entropy}, else: {:error, :bad_checksum}
    end
  end

  @doc "Frase válida?"
  @spec valid?(String.t()) :: boolean()
  def valid?(mnemonic), do: match?({:ok, _}, to_entropy(mnemonic))

  @doc """
  Semente de 64 bytes. Com `passphrase = \"\"` é a carteira "comum"; qualquer outra
  passphrase abre uma carteira diferente (e esquecer a passphrase perde os fundos).
  """
  @spec to_seed(String.t(), String.t()) :: <<_::512>>
  def to_seed(mnemonic, passphrase \\ "") when is_binary(mnemonic) and is_binary(passphrase) do
    :crypto.pbkdf2_hmac(
      :sha512,
      normalize(mnemonic),
      "mnemonic" <> :unicode.characters_to_nfkd_binary(passphrase),
      2048,
      64
    )
  end

  defp normalize(s), do: s |> String.trim() |> :unicode.characters_to_nfkd_binary()

  defp indexes(words) do
    Enum.reduce_while(words, {:ok, []}, fn w, {:ok, acc} ->
      case Map.fetch(@index, w) do
        {:ok, i} -> {:cont, {:ok, [i | acc]}}
        :error -> {:halt, {:error, :unknown_word}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end
end
