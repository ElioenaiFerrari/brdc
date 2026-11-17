defmodule BrdcLedger.Block do
  @moduledoc """
  Bloco (Fase 2): cabeçalho + transações, executado de forma **atômica**: se qualquer
  transação for inválida, o bloco inteiro é recusado e o estado não muda.

  O cabeçalho carrega `height`, `prev_hash`, `proposer`, `signers` (quem assinou o certificado
  de commit, fornecido pelo consenso na Fase 3), `tx_root` e `state_root`. A taxa total é
  repartida entre os `signers` em partes iguais; o resto da divisão vai para o `proposer`
  (ADR-0014). Sem blocos vazios (ADR-0003).
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.{Executor, State, Tx}

  @enforce_keys [:height, :prev_hash, :proposer, :signers, :txs]
  defstruct [:height, :prev_hash, :proposer, :signers, :txs, :state_root]

  @type t :: %__MODULE__{
          height: pos_integer(),
          prev_hash: nil | <<_::256>>,
          proposer: <<_::256>>,
          signers: [<<_::256>>],
          txs: [Tx.t()],
          state_root: nil | <<_::256>>
        }

  @doc "Raiz de Merkle das transações (pelos ids)."
  @spec tx_root([Tx.t()]) :: <<_::256>>
  def tx_root(txs) do
    leaves = Enum.map(txs, &Hash.tagged("brdc/block/tx", Tx.id(&1)))
    Hash.tagged("brdc/block/txs", Encoding.encode([{:list, {:fixed, 32}}], [leaves]))
  end

  @doc "Hash do cabeçalho (é o que o consenso assina)."
  @spec hash(t()) :: <<_::256>>
  def hash(%__MODULE__{} = b) do
    Hash.tagged(
      "brdc/block",
      Encoding.encode(
        [:u64, :bytes, {:fixed, 32}, {:list, {:fixed, 32}}, {:fixed, 32}, {:fixed, 32}],
        [b.height, b.prev_hash || <<>>, b.proposer, b.signers, tx_root(b.txs), b.state_root]
      )
    )
  end

  @doc """
  Executa as transações sobre `state` e devolve o bloco com `state_root` preenchido e o novo estado.
  Usado por quem **propõe** o bloco.
  """
  @spec build(State.t(), <<_::256>>, [<<_::256>>], [Tx.t()]) ::
          {:ok, t(), State.t()} | {:error, term()}
  def build(%State{} = state, proposer, signers, txs) do
    block = %__MODULE__{
      height: state.height + 1,
      prev_hash: state.last_hash,
      proposer: proposer,
      signers: signers,
      txs: txs
    }

    with {:ok, new_state} <- execute(state, block) do
      {:ok, %{block | state_root: State.root(new_state)}, new_state}
    end
  end

  @doc """
  Valida e executa um bloco recebido de outro nó: confere altura, `prev_hash`, limites,
  `state_root` e aplica as transações. Devolve o novo estado ou o motivo da recusa.
  """
  @spec apply(State.t(), t()) :: {:ok, State.t()} | {:error, term()}
  def apply(%State{} = state, %__MODULE__{} = block) do
    with {:ok, new_state} <- execute(state, block),
         :ok <-
           if(State.root(new_state) == block.state_root, do: :ok, else: {:error, :bad_state_root}) do
      {:ok, new_state}
    end
  end

  defp execute(%State{params: p} = state, %__MODULE__{} = b) do
    with :ok <- check(b.height == state.height + 1, :bad_height),
         :ok <- check(b.prev_hash == state.last_hash, :bad_prev_hash),
         :ok <- check(b.txs != [], :empty_block),
         :ok <- check(length(b.txs) <= p.max_block_txs, :too_many_txs),
         :ok <-
           check(
             Enum.sum(Enum.map(b.txs, &byte_size(Tx.encode(&1)))) <= p.max_block_bytes,
             :too_big
           ),
         :ok <- check(b.signers != [] and b.signers == Enum.uniq(b.signers), :bad_signers),
         :ok <- check(b.proposer in b.signers, :proposer_not_signer),
         {:ok, s1, fees} <- run_txs(state, b.txs) do
      s2 = distribute(s1, fees, b)
      {:ok, %{s2 | height: b.height, last_hash: block_hash_for(b, s2)}}
    end
  end

  # O hash do bloco depende do state_root; em `build` ele ainda não existe, então o
  # last_hash definitivo é recalculado com a raiz do estado resultante.
  defp block_hash_for(b, s), do: hash(%{b | state_root: State.root(s)})

  defp run_txs(state, txs) do
    Enum.reduce_while(txs, {:ok, state, 0}, fn tx, {:ok, s, fees} ->
      case Executor.apply_tx(s, tx) do
        {:ok, s2, fee} -> {:cont, {:ok, s2, fees + fee}}
        {:error, reason} -> {:halt, {:error, {:invalid_tx, Tx.id(tx), reason}}}
      end
    end)
  end

  defp distribute(s, 0, _b), do: s

  defp distribute(s, fees, %{signers: signers, proposer: proposer}) do
    share = div(fees, length(signers))
    rest = fees - share * length(signers)

    Enum.reduce(signers, s, fn addr, acc ->
      credit(acc, addr, share + if(addr == proposer, do: rest, else: 0))
    end)
  end

  defp credit(s, _addr, 0), do: s

  defp credit(s, addr, amount) do
    a = State.account(s, addr)
    State.put_account(s, addr, %{a | balance: a.balance + amount})
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
