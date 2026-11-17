defmodule BrdcNode.Node do
  @moduledoc """
  Nó local de **um validador** (Fase 7, primeiro passo): guarda o estado do ledger, recebe transações,
  valida cada uma contra o estado **como ficaria com as pendentes** e produz blocos sem nunca produzir
  bloco vazio. Com um único validador, o bloco é decidido por ele mesmo (o motor BFT e a rede entre
  validadores ainda não estão ligados a este nó: é o passo seguinte).

  - **Mempool** em ordem de chegada (por conta, o nonce já impõe a ordem), com teto.
  - **Bloco** quando há transação pendente, depois de `block_interval_ms` (o intervalo de agrupamento é a
    decisão pendente P3; aqui é só um parâmetro). `:manual` desliga o relógio e os testes chamam `produce/1`.
  - **Horário do bloco** vem do relógio injetado e nunca decresce (ADR-0016).
  - As taxas vão para a conta do próprio validador.
  - **Tudo em memória** (ADR-0012 pendente): reiniciar o nó volta à gênese.
  """
  use GenServer
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Block, Executor, State, Tx}
  alias BrdcNode.{Genesis, Proposals}

  @max_mempool 10_000

  # --- API ---------------------------------------------------------------------------------

  @doc """
  Opções: `:genesis` (`BrdcNode.Genesis`), `:seed` (chave do validador, 32 bytes), `:block_interval_ms`
  (padrão 1000, ou `:manual`), `:clock` (`fn -> segundos end`), `:name`.
  """
  def start_link(opts) do
    {gen, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen)
  end

  @doc "Estado público do nó."
  @spec status(GenServer.server()) :: map()
  def status(node), do: GenServer.call(node, :status)

  @doc "Saldo e nonce de um endereço (hash de 32 bytes). `pending: true` considera as pendentes."
  @spec account(GenServer.server(), <<_::256>>, keyword()) :: %{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }
  def account(node, addr, opts \\ []),
    do: GenServer.call(node, {:account, addr, Keyword.get(opts, :pending, false)})

  @doc """
  Contratos entre partes de um endereço (como parte A ou B), do estado **confirmado**.
  """
  @spec contracts_of(GenServer.server(), <<_::256>>) :: [map()]
  def contracts_of(node, addr), do: GenServer.call(node, {:contracts_of, addr})

  @doc "Credenciais cujo titular é o endereço (estado confirmado)."
  @spec credentials_of(GenServer.server(), <<_::256>>) :: [map()]
  def credentials_of(node, addr), do: GenServer.call(node, {:credentials_of, addr})

  @doc "Bens de um endereço: os que ele possui e os que ele está comprando (com a negociação, se houver)."
  @spec assets_of(GenServer.server(), <<_::256>>) :: [map()]
  def assets_of(node, addr), do: GenServer.call(node, {:assets_of, addr})

  @doc "Tipos de credencial cujo órgão inclui a chave pública `pub` (quem pode assinar emissões)."
  @spec types_for(GenServer.server(), <<_::256>>) :: [map()]
  def types_for(node, pub), do: GenServer.call(node, {:types_for, pub})

  @doc "Propõe uma emissão de credencial para assinatura coletiva (os campos; o documento é recalculado)."
  @spec propose(GenServer.server(), Proposals.fields()) :: {:ok, <<_::256>>} | {:error, atom()}
  def propose(node, fields), do: GenServer.call(node, {:propose, fields})

  @doc "Aprovação de um membro (`chave ‖ assinatura`) a uma proposta. Devolve quantas aprovações há."
  @spec approve(GenServer.server(), <<_::256>>, binary()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def approve(node, id, approval), do: GenServer.call(node, {:approve, id, approval})

  @doc "Propostas abertas dos órgãos de que a chave faz parte, com as aprovações e o limite."
  @spec proposals_for(GenServer.server(), <<_::256>>) :: [map()]
  def proposals_for(node, pub), do: GenServer.call(node, {:proposals_for, pub})

  @doc "Recebe uma transação já assinada (bytes). Devolve o id ou o motivo da recusa."
  @spec submit(GenServer.server(), binary()) :: {:ok, <<_::256>>} | {:error, atom()}
  def submit(node, bin) when is_binary(bin), do: GenServer.call(node, {:submit, bin})

  @doc "Produz um bloco agora, se houver transação pendente (testes e modo manual)."
  @spec produce(GenServer.server()) :: {:ok, pos_integer()} | :nothing
  def produce(node), do: GenServer.call(node, :produce)

  @doc "Quem se inscreve recebe `{:brdc_block, altura, [txid]}` a cada bloco."
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(node), do: GenServer.call(node, {:subscribe, self()})

  @doc "O bloco de uma altura (os últimos 1.000 ficam na memória)."
  @spec block(GenServer.server(), pos_integer()) :: {:ok, Block.t()} | :error
  def block(node, height), do: GenServer.call(node, {:block, height})

  # --- servidor ------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    genesis = Keyword.fetch!(opts, :genesis)
    seed = Keyword.fetch!(opts, :seed)
    state = genesis |> Genesis.ledger_params() |> State.new()

    {:ok,
     %{
       genesis: genesis,
       seed: seed,
       proposer: Address.hash(Ed25519.public_key(seed)),
       state: state,
       pending_state: state,
       mempool: [],
       blocks: %{},
       proposals: Proposals.new(),
       interval: Keyword.get(opts, :block_interval_ms, 1_000),
       clock: Keyword.get(opts, :clock, fn -> System.os_time(:second) end),
       timer: nil,
       subscribers: %{}
     }}
  end

  @impl true
  def handle_call(:status, _from, s) do
    st = s.state

    {:reply,
     %{
       chain_id: st.params.chain_id,
       height: st.height,
       time: st.time,
       supply: State.supply(st),
       last_hash: st.last_hash,
       pending: length(s.mempool),
       transfer_base: st.params.transfer_base,
       per_byte: st.params.per_byte,
       contract_fee: st.params.contract_fee,
       credential_fee: st.params.credential_fee,
       asset_step_fee: st.params.asset_step_fee,
       genesis_hash: Genesis.hash(s.genesis)
     }, s}
  end

  def handle_call({:account, addr, pending?}, _from, s) do
    st = if pending?, do: s.pending_state, else: s.state
    {:reply, State.account(st, addr), s}
  end

  def handle_call({:contracts_of, addr}, _from, s) do
    list =
      for {id, c} <- Enum.sort(s.state.contracts), c.a == addr or c.b == addr do
        Map.put(c, :id, id)
      end

    {:reply, list, s}
  end

  def handle_call({:credentials_of, addr}, _from, s) do
    {:reply,
     for({id, c} <- Enum.sort(s.state.credentials), c.subject == addr, do: Map.put(c, :id, id)),
     s}
  end

  def handle_call({:assets_of, addr}, _from, s) do
    st = s.state

    mine =
      for {id, a} <- Enum.sort(st.assets), a.owner == addr or buying?(st.deals[id], addr) do
        role = if a.owner == addr, do: "owner", else: "buyer"

        %{
          id: id,
          class: a.class,
          meta: a.meta,
          rev: a.rev,
          liens: map_size(a.liens),
          role: role,
          deal: st.deals[id],
          veto_window: st.classes[a.class].veto_window
        }
      end

    {:reply, mine, s}
  end

  def handle_call({:types_for, pub}, _from, s) do
    {:reply,
     for({id, t} <- Enum.sort(s.state.cred_types), pub in t.organ, do: Map.put(t, :id, id)), s}
  end

  def handle_call({:propose, fields}, _from, s) do
    case Proposals.put(s.proposals, s.state, fields) do
      {:ok, store, id} -> {:reply, {:ok, id}, %{s | proposals: store}}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:approve, id, approval}, _from, s) do
    case Proposals.approve(s.proposals, s.state, id, approval) do
      {:ok, store, n} -> {:reply, {:ok, n}, %{s | proposals: store}}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:proposals_for, pub}, _from, s) do
    {:reply, Proposals.list_for(s.proposals, s.state, pub), s}
  end

  def handle_call({:submit, bin}, _from, s) do
    with {:ok, tx} <- Tx.decode(bin),
         :ok <- check(length(s.mempool) < @max_mempool, :mempool_full),
         :ok <- check(not Enum.any?(s.mempool, &(Tx.id(&1) == Tx.id(tx))), :duplicate),
         {:ok, pending, _fee} <- Executor.apply_tx(at_next_block(s), tx) do
      s = %{s | mempool: s.mempool ++ [tx], pending_state: pending}
      {:reply, {:ok, Tx.id(tx)}, arm(s)}
    else
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call(:produce, _from, s) do
    case produce_block(s) do
      {:ok, s2, height} -> {:reply, {:ok, height}, s2}
      {:nothing, s2} -> {:reply, :nothing, s2}
    end
  end

  def handle_call({:subscribe, pid}, _from, s) do
    ref = Process.monitor(pid)
    {:reply, :ok, %{s | subscribers: Map.put(s.subscribers, ref, pid)}}
  end

  def handle_call({:block, height}, _from, s) do
    {:reply, Map.fetch(s.blocks, height), s}
  end

  @impl true
  def handle_info(:produce, s) do
    s = %{s | timer: nil}

    case produce_block(s) do
      {:ok, s2, _} -> {:noreply, arm(s2)}
      {:nothing, s2} -> {:noreply, s2}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _}, s),
    do: {:noreply, %{s | subscribers: Map.delete(s.subscribers, ref)}}

  def handle_info(_msg, s), do: {:noreply, s}

  # --- produção de blocos ----------------------------------------------------------------------

  # só arma o relógio se há o que produzir e ainda não há relógio armado
  defp arm(%{interval: :manual} = s), do: s
  defp arm(%{mempool: []} = s), do: s

  defp arm(%{timer: t} = s) when t != nil, do: s
  defp arm(s), do: %{s | timer: Process.send_after(self(), :produce, s.interval)}

  defp buying?(nil, _addr), do: false
  defp buying?(deal, addr), do: deal.buyer == addr

  # sem blocos vazios, o horário do último bloco fica parado; o próximo bloco usa o relógio (nunca menos que o último).
  # A transação é conferida nesse horário (senão uma janela já vencida pareceria aberta).
  defp at_next_block(s), do: %{s.pending_state | time: max(s.clock.(), s.state.time)}

  defp produce_block(%{mempool: []} = s), do: {:nothing, s}

  defp produce_block(s) do
    {txs, rest} = take(s.mempool, s.state.params)
    time = max(s.clock.(), s.state.time)

    case Block.build(s.state, s.proposer, [s.proposer], txs, time) do
      {:ok, block, new_state} ->
        s = %{s | state: new_state, mempool: rest, blocks: keep(s.blocks, block)}
        s = %{s | proposals: Proposals.prune(s.proposals, new_state)}
        s = %{s | pending_state: replay(new_state, rest)}
        notify(s, block)
        {:ok, s, block.height}

      {:error, {:invalid_tx, id, _reason}} ->
        # não deveria acontecer (cada tx foi validada ao entrar); descarta a ofensora e tenta de novo
        s = %{s | mempool: Enum.reject(s.mempool, &(Tx.id(&1) == id))}
        s = %{s | pending_state: replay(s.state, s.mempool)}
        produce_block(s)

      {:error, _} ->
        {:nothing, s}
    end
  end

  # respeita os limites de bloco dos parâmetros (quantidade e bytes)
  defp take(mempool, params) do
    {taken, _bytes} =
      Enum.reduce_while(mempool, {[], 0}, fn tx, {acc, bytes} ->
        size = byte_size(Tx.encode(tx))

        if length(acc) < params.max_block_txs and bytes + size <= params.max_block_bytes,
          do: {:cont, {[tx | acc], bytes + size}},
          else: {:halt, {acc, bytes}}
      end)

    taken = Enum.reverse(taken)
    {taken, Enum.drop(mempool, length(taken))}
  end

  defp replay(state, txs) do
    Enum.reduce(txs, state, fn tx, acc ->
      case Executor.apply_tx(acc, tx) do
        {:ok, next, _fee} -> next
        {:error, _} -> acc
      end
    end)
  end

  defp keep(blocks, block) do
    blocks |> Map.put(block.height, block) |> Map.delete(block.height - 1_000)
  end

  defp notify(s, block) do
    ids = Enum.map(block.txs, &Tx.id/1)
    for {_ref, pid} <- s.subscribers, do: send(pid, {:brdc_block, block.height, ids})
    :ok
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
