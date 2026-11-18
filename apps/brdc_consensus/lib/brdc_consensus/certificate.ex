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

  @codec [:u64, :u64, {:fixed, 32}, {:list, :bytes}]

  @doc "Codificação para a rede e para o disco (cada voto com `Vote.encode/1`)."
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = c) do
    BrdcCrypto.Encoding.encode(@codec, [
      c.height,
      c.round,
      c.block_hash,
      Enum.map(c.votes, &Vote.encode/1)
    ])
  end

  @doc "Decodifica; recusa lixo e sobras. As assinaturas e o quórum são conferidos por `verify/3`."
  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(bin) when is_binary(bin) do
    with {:ok, [height, round, hash, raw]} <- BrdcCrypto.Encoding.decode(@codec, bin),
         {:ok, votes} <- decode_votes(raw) do
      {:ok, %__MODULE__{height: height, round: round, block_hash: hash, votes: votes}}
    else
      _ -> {:error, :malformed}
    end
  end

  defp decode_votes(raw) do
    Enum.reduce_while(raw, {:ok, []}, fn bin, {:ok, acc} ->
      case Vote.decode(bin) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> :error
    end
  end

  @doc "Chaves públicas de quem assinou."
  @spec signers(t()) :: [<<_::256>>]
  def signers(%__MODULE__{votes: votes}), do: Enum.map(votes, & &1.voter)
end
