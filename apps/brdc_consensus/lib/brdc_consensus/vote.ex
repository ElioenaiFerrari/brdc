defmodule BrdcConsensus.Vote do
  @moduledoc """
  Voto assinado (prevote ou precommit) de um validador numa altura e rodada (Fase 3).
  `block_hash = nil` é o **voto nulo** ("não vi bloco válido a tempo").
  A assinatura cobre `chain_id`, tipo, altura, rodada e hash: um voto não vale em outra rede,
  altura, rodada ou tipo.
  """
  alias BrdcCrypto.{Ed25519, Encoding, Hash}

  @enforce_keys [:type, :height, :round, :block_hash, :voter, :signature]
  defstruct [:type, :height, :round, :block_hash, :voter, :signature]

  @type t :: %__MODULE__{
          type: :prevote | :precommit,
          height: non_neg_integer(),
          round: non_neg_integer(),
          block_hash: nil | <<_::256>>,
          voter: <<_::256>>,
          signature: <<_::512>>
        }

  @codec [:u8, :u64, :u64, :bytes, {:fixed, 32}, {:fixed, 64}]

  @doc "Codificação para a rede e para o diário em disco (ordem fixa, sem ambiguidade)."
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = v) do
    Encoding.encode(@codec, [
      type_byte(v.type),
      v.height,
      v.round,
      v.block_hash || <<>>,
      v.voter,
      v.signature
    ])
  end

  @doc "Decodifica; recusa lixo, sobras, tipo desconhecido e hash de tamanho estranho (a assinatura é conferida por `valid?/2`)."
  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(bin) when is_binary(bin) do
    with {:ok, [type, height, round, hash, voter, sig]} <- Encoding.decode(@codec, bin),
         {:ok, type} <- type_from_byte(type),
         true <- byte_size(hash) in [0, 32] do
      {:ok,
       %__MODULE__{
         type: type,
         height: height,
         round: round,
         block_hash: if(hash == <<>>, do: nil, else: hash),
         voter: voter,
         signature: sig
       }}
    else
      _ -> {:error, :malformed}
    end
  end

  @doc "O que é assinado."
  @spec doc(
          String.t(),
          :prevote | :precommit,
          non_neg_integer(),
          non_neg_integer(),
          nil | binary()
        ) ::
          binary()
  def doc(chain_id, type, height, round, hash) do
    Hash.tagged(
      "brdc/vote",
      Encoding.encode(
        [:string, :u8, :u64, :u64, :bytes],
        [chain_id, type_byte(type), height, round, hash || <<>>]
      )
    )
  end

  @doc "Cria e assina um voto."
  @spec sign(
          String.t(),
          :prevote | :precommit,
          non_neg_integer(),
          non_neg_integer(),
          nil | binary(),
          <<_::256>>
        ) ::
          t()
  def sign(chain_id, type, height, round, hash, seed) do
    sig = Ed25519.sign(doc(chain_id, type, height, round, hash), seed)

    %__MODULE__{
      type: type,
      height: height,
      round: round,
      block_hash: hash,
      voter: Ed25519.public_key(seed),
      signature: sig
    }
  end

  @doc "A assinatura confere?"
  @spec valid?(String.t(), t()) :: boolean()
  def valid?(chain_id, %__MODULE__{} = v) do
    Ed25519.verify(doc(chain_id, v.type, v.height, v.round, v.block_hash), v.signature, v.voter)
  end

  defp type_byte(:prevote), do: 1
  defp type_byte(:precommit), do: 2

  defp type_from_byte(1), do: {:ok, :prevote}
  defp type_from_byte(2), do: {:ok, :precommit}
  defp type_from_byte(_), do: :error
end
