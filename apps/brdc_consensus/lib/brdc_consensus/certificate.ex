defmodule BrdcConsensus.Certificate do
  @moduledoc """
  Certificado de commit (Fase 3): os precommits de **mais de 2/3** dos validadores no mesmo
  bloco. Quem não participou do consenso (um nó que sincroniza, a Suite, o explorador) confere
  o certificado sozinho e passa a **confiar no bloco sem confiar em quem o entregou**.
  Também diz **quem assinou** o bloco (o que o explorador mostra).
  """
  alias BrdcConsensus.Vote

  @enforce_keys [:height, :round, :block_hash, :votes]
  defstruct [:height, :round, :block_hash, :votes]

  @type t :: %__MODULE__{
          height: non_neg_integer(),
          round: non_neg_integer(),
          block_hash: <<_::256>>,
          votes: [Vote.t()]
        }

  @doc "Quórum: mais de 2/3 de `n`."
  @spec quorum?(non_neg_integer(), pos_integer()) :: boolean()
  def quorum?(count, n), do: count * 3 > 2 * n

  @doc "Confere o certificado contra o conjunto de validadores em vigor naquela altura."
  @spec verify(t(), String.t(), [<<_::256>>]) :: :ok | {:error, atom()}
  def verify(%__MODULE__{} = c, chain_id, validators) do
    voters = Enum.map(c.votes, & &1.voter)

    with :ok <- check(Enum.all?(c.votes, &same_slot?(&1, c)), :mismatched_votes),
         :ok <- check(Enum.all?(c.votes, &(&1.block_hash == c.block_hash)), :different_block),
         :ok <- check(length(voters) == length(Enum.uniq(voters)), :duplicate_voter),
         :ok <- check(Enum.all?(voters, &(&1 in validators)), :unknown_voter),
         :ok <- check(Enum.all?(c.votes, &Vote.valid?(chain_id, &1)), :bad_signature) do
      check(quorum?(length(voters), length(validators)), :no_quorum)
    end
  end

  defp same_slot?(v, c), do: v.type == :precommit and v.height == c.height and v.round == c.round

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}

  @doc "Chaves públicas de quem assinou."
  @spec signers(t()) :: [<<_::256>>]
  def signers(%__MODULE__{votes: votes}), do: Enum.map(votes, & &1.voter)
end
