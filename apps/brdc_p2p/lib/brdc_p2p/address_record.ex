defmodule BrdcP2p.AddressRecord do
  @moduledoc """
  Registro de endereço assinado (Fase 4): o validador declara **onde** ele atende
  (`host:port`) e assina com a chave de consenso. Quem recebe confere a assinatura; ninguém
  consegue inventar o endereço de outro validador. `seq` cresce a cada mudança, então o
  registro mais novo vence e um antigo reenviado é recusado.
  """
  alias BrdcCrypto.{Ed25519, Encoding, Hash}

  @enforce_keys [:chain_id, :validator, :host, :port, :seq, :signature]
  defstruct [:chain_id, :validator, :host, :port, :seq, :signature]

  @type t :: %__MODULE__{
          chain_id: String.t(),
          validator: <<_::256>>,
          host: String.t(),
          port: 1..65_535,
          seq: non_neg_integer(),
          signature: <<_::512>>
        }

  @schema [:string, {:fixed, 32}, :string, :u32, :u64, {:fixed, 64}]
  @max_host 253

  @spec doc(String.t(), <<_::256>>, String.t(), non_neg_integer(), non_neg_integer()) :: binary()
  def doc(chain_id, validator, host, port, seq) do
    Hash.tagged(
      "brdc/p2p/address",
      Encoding.encode([:string, {:fixed, 32}, :string, :u32, :u64], [
        chain_id,
        validator,
        host,
        port,
        seq
      ])
    )
  end

  @doc "Cria e assina o registro. Falha se o host ou a porta forem inválidos."
  @spec sign(String.t(), <<_::256>>, String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, t()} | {:error, :invalid_host | :invalid_port}
  def sign(chain_id, seed, host, port, seq) do
    validator = Ed25519.public_key(seed)

    with :ok <- check_host(host), :ok <- check_port(port) do
      sig = Ed25519.sign(doc(chain_id, validator, host, port, seq), seed)

      {:ok,
       %__MODULE__{
         chain_id: chain_id,
         validator: validator,
         host: host,
         port: port,
         seq: seq,
         signature: sig
       }}
    end
  end

  @doc "Assinatura, host e porta são válidos?"
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = r) do
    check_host(r.host) == :ok and check_port(r.port) == :ok and
      Ed25519.verify(
        doc(r.chain_id, r.validator, r.host, r.port, r.seq),
        r.signature,
        r.validator
      )
  end

  @doc "Codifica para a rede."
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = r),
    do: Encoding.encode(@schema, [r.chain_id, r.validator, r.host, r.port, r.seq, r.signature])

  @doc "Decodifica (sem confiar: quem usa deve chamar `valid?/1`)."
  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(bin) when is_binary(bin) do
    case Encoding.decode(@schema, bin) do
      {:ok, [chain_id, validator, host, port, seq, signature]} ->
        {:ok,
         %__MODULE__{
           chain_id: chain_id,
           validator: validator,
           host: host,
           port: port,
           seq: seq,
           signature: signature
         }}

      _ ->
        {:error, :malformed}
    end
  end

  # nome de máquina ou IP: letras, dígitos, ponto, hífen e dois-pontos (IPv6); nada de espaço ou barra
  defp check_host(host) when is_binary(host) and byte_size(host) in 1..@max_host do
    if host =~ ~r/\A[A-Za-z0-9.\-:]+\z/, do: :ok, else: {:error, :invalid_host}
  end

  defp check_host(_), do: {:error, :invalid_host}

  defp check_port(port) when is_integer(port) and port in 1..65_535, do: :ok
  defp check_port(_), do: {:error, :invalid_port}
end
