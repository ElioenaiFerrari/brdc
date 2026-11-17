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

  @spec valid?(String.t(), t()) :: boolean()
  def valid?(chain_id, %__MODULE__{} = p) do
    Ed25519.verify(
      doc(chain_id, p.height, p.round, p.valid_round, p.block_hash),
      p.signature,
      p.proposer
    )
  end
end
