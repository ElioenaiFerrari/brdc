defmodule BrdcCrypto.Ed25519 do
  @moduledoc """
  Assinatura Ed25519 sobre `:crypto` (OTP), Fase 1 (ADR-0005).

  A chave privada é a semente de 32 bytes. A chave pública tem 32 bytes.
  Assinaturas têm 64 bytes e são determinísticas (mesma mensagem, mesma assinatura).
  """

  @type seed :: <<_::256>>
  @type public_key :: <<_::256>>
  @type signature :: <<_::512>>

  @doc "Chave pública a partir da semente privada."
  @spec public_key(seed()) :: public_key()
  def public_key(<<_::256>> = seed) do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519, seed)
    pub
  end

  @doc "Assina `message` com a semente privada."
  @spec sign(binary(), seed()) :: signature()
  def sign(message, <<_::256>> = seed) when is_binary(message) do
    :crypto.sign(:eddsa, :none, message, [seed, :ed25519])
  end

  @doc "Confere uma assinatura. Entradas malformadas dão `false`, nunca exceção."
  @spec verify(binary(), signature(), public_key()) :: boolean()
  def verify(message, <<_::512>> = sig, <<_::256>> = pub) when is_binary(message) do
    :crypto.verify(:eddsa, :none, message, sig, [pub, :ed25519])
  rescue
    _ -> false
  end

  def verify(_message, _sig, _pub), do: false
end
