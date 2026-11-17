defmodule BrdcCrypto.Address do
  @moduledoc """
  Endereço BRDC (ADR-0010), Fase 1: `brdc1…` em bech32m.

  `address = bech32m("brdc", tagged_hash("brdc/addr", chave_pública))` (32 bytes).
  O checksum do bech32m detecta erro de digitação; o endereço não revela a chave
  pública até a primeira assinatura.
  """
  alias BrdcCrypto.{Bech32m, Hash}

  @hrp "brdc"

  @doc "Prefixo legível dos endereços."
  @spec hrp() :: String.t()
  def hrp, do: @hrp

  @doc "Endereço de uma chave pública Ed25519 (32 bytes)."
  @spec from_public_key(<<_::256>>) :: String.t()
  def from_public_key(<<_::256>> = pub), do: Bech32m.encode(@hrp, hash(pub))

  @doc "Os 32 bytes de hash que o endereço carrega (é o que o livro-razão guarda)."
  @spec hash(<<_::256>>) :: <<_::256>>
  def hash(<<_::256>> = pub), do: Hash.tagged("brdc/addr", pub)

  @doc "Valida um endereço `brdc1…` e devolve os 32 bytes de hash."
  @spec decode(String.t()) :: {:ok, <<_::256>>} | {:error, atom()}
  def decode(address) when is_binary(address) do
    case Bech32m.decode(address) do
      {:ok, @hrp, <<_::256>> = h} -> {:ok, h}
      {:ok, @hrp, _} -> {:error, :bad_size}
      {:ok, _other, _} -> {:error, :wrong_prefix}
      {:error, _} = err -> err
    end
  end

  @doc "A chave pública corresponde ao endereço?"
  @spec matches?(String.t(), <<_::256>>) :: boolean()
  def matches?(address, <<_::256>> = pub) do
    decode(address) == {:ok, hash(pub)}
  end
end
