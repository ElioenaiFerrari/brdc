defmodule BrdcConsensus.Proposal do
  @moduledoc """
  Proposta de bloco do proponente da rodada (Fase 3). `valid_round` é a rodada em que o
  proponente viu mais de 2/3 de prevotes neste mesmo bloco (`-1` se é um bloco novo): serve
  para destravar validadores presos a outro bloco. A assinatura cobre o **hash** do bloco; o
  bloco em si viaja junto e é conferido contra o hash.
  """
  alias BrdcCrypto.{Ed25519, Encoding, Hash}

  @enforce_keys [:height, :round, :valid_round, :block_hash, :block, :proposer, :signature]
  defstruct [:height, :round, :valid_round, :block_hash, :block, :proposer, :signature]

  @type t :: %__MODULE__{
          height: non_neg_integer(),
          round: non_neg_integer(),
          valid_round: integer(),
          block_hash: <<_::256>>,
          block: term(),
          proposer: <<_::256>>,
          signature: <<_::512>>
        }

  @spec doc(String.t(), non_neg_integer(), non_neg_integer(), integer(), binary()) :: binary()
  def doc(chain_id, height, round, valid_round, hash) do
    Hash.tagged(
      "brdc/proposal",
      Encoding.encode(
        [:string, :u64, :u64, :u64, {:fixed, 32}],
        [chain_id, height, round, valid_round + 1, hash]
      )
    )
  end

  @spec sign(
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          integer(),
          term(),
          binary(),
          <<_::256>>
        ) :: t()
  def sign(chain_id, height, round, valid_round, block, hash, seed) do
    %__MODULE__{
      height: height,
      round: round,
      valid_round: valid_round,
      block_hash: hash,
      block: block,
      proposer: Ed25519.public_key(seed),
      signature: Ed25519.sign(doc(chain_id, height, round, valid_round, hash), seed)
    }
  end

  @codec [:u64, :u64, :u64, {:fixed, 32}, :bytes, {:fixed, 32}, {:fixed, 64}]

  @doc """
  Codificação para a rede e para o diário em disco. O bloco é opaco para o consenso: quem chama traz
  `block_encode` (bloco → bytes). O `valid_round` vai somado de 1 (assim o `-1` cabe num inteiro sem sinal).
  """
  @spec encode(t(), (term() -> binary())) :: binary()
  def encode(%__MODULE__{} = p, block_encode) do
    Encoding.encode(@codec, [
      p.height,
      p.round,
      p.valid_round + 1,
      p.block_hash,
      block_encode.(p.block),
      p.proposer,
      p.signature
    ])
  end

  @doc "Decodifica com `block_decode` (bytes → `{:ok, bloco}` ou erro); recusa lixo e sobras."
  @spec decode(binary(), (binary() -> {:ok, term()} | {:error, term()})) ::
          {:ok, t()} | {:error, :malformed}
  def decode(bin, block_decode) when is_binary(bin) do
    with {:ok, [height, round, vr1, hash, block_bin, proposer, sig]} <-
           Encoding.decode(@codec, bin),
         {:ok, block} <- block_decode.(block_bin) do
      {:ok,
       %__MODULE__{
         height: height,
         round: round,
         valid_round: vr1 - 1,
         block_hash: hash,
         block: block,
         proposer: proposer,
         signature: sig
       }}
    else
      _ -> {:error, :malformed}
    end
  end

  @spec valid?(String.t(), t()) :: boolean()
  def valid?(chain_id, %__MODULE__{} = p) do
    Ed25519.verify(
      doc(chain_id, p.height, p.round, p.valid_round, p.block_hash),
      p.signature,
      p.proposer
    )
  end
end
