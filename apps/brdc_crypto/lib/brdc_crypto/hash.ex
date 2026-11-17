defmodule BrdcCrypto.Hash do
  @moduledoc """
  Hash etiquetado (ADR-0011), Fase 1.

  `tagged(tag, data) = SHA3-256(<<byte_size(tag)::32>> <> tag <> data)`.

  O prefixo de domínio (`tag`) garante que o hash de uma coisa (ex.: uma
  transação) nunca seja aceito como o hash de outra (ex.: um bloco).
  """

  @type tag :: String.t()

  @doc "SHA3-256 puro (32 bytes)."
  @spec sha3(iodata()) :: <<_::256>>
  def sha3(data), do: :crypto.hash(:sha3_256, data)

  @doc "SHA3-256 com prefixo de domínio: tamanho da etiqueta (4 bytes) + etiqueta + dados."
  @spec tagged(tag(), iodata()) :: <<_::256>>
  def tagged(tag, data) when is_binary(tag) do
    sha3([<<byte_size(tag)::32>>, tag, data])
  end

  @doc "Binário em hexadecimal minúsculo."
  @spec hex(binary()) :: String.t()
  def hex(bin) when is_binary(bin), do: Base.encode16(bin, case: :lower)
end
