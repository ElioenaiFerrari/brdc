defmodule BrdcNode.Replica do
  @moduledoc """
  Réplica de um validador (M2): liga o **motor BFT** (`BrdcConsensus.Engine`, uma altura por vez) ao **nó**
  (`BrdcNode.Node`: estado, mempool, disco), à **rede** entre validadores (`BrdcNode.Peers`) e ao **diário de
  segurança** (`BrdcNode.ConsensusWal`, ADR-0026).

  ## O que faz
  - **Sem blocos vazios:** a altura só começa quando há transação pendente (depois de `interval_ms` de
    agrupamento) ou quando chega uma mensagem de consenso daquela altura (alguém já tem o que propor).
  - **Espalha transações** a todos os pares (o nó avisa cada transação nova) e aceita as dos pares.
  - **Roda o motor:** entrega propostas e votos, dispara prazos, pede o bloco quando é o proponente.
  - **Antes de transmitir** qualquer proposta ou voto próprio, grava no diário; se a gravação falhar, a réplica
    **para** (falha fechada: nada é transmitido) em vez de arriscar a equivocação.
  - **Decisão:** confirma no nó o bloco com o certificado, esvazia o diário, avisa os pares e segue.
  - **Sincroniza** quem está atrás: pede blocos ao par que está à frente e **confere o certificado de cada um**
    antes de aceitar (não confia em quem entrega).
  - **Reinício:** se o diário tem mensagens da altura em curso, retoma com `Engine.restore/2`.

  ## Limites honestos
  O motor não retransmite mensagens de uma rodada; quem chega atrasado a uma altura se atualiza pela
  sincronização (blocos com certificado) ou pelas rodadas seguintes. Ver o ADR-0026.
  """
  use GenServer
  alias BrdcConsensus.{Engine, Proposal}
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Block, Tx}
  alias BrdcNode.{ConsensusWal, Node, Peers}
  alias BrdcP2p.Guard
  require Logger

  @default_timeouts %{propose: 2_000, prevote: 1_000, precommit: 1_000, delta: 500}
  @sync_batch 16
  @sync_timeout 3_000
  # cabe num quadro do canal (1 MiB) com folga para o envelope
  @max_reply_bytes 900_000

  # --- API ---------------------------------------------------------------------------------

  @doc """
  Opções: `:node` (pid do `BrdcNode.Node`, em modo manual), `:genesis`, `:seed`, `:data_dir` (diário do
  consenso; sem ele não há diário e a réplica **não é segura contra reinício**), `:port` (0 = livre),
  `:peers` (`[%{pub:, host:, port:}]`), `:interval_ms` (agrupamento, padrão 1000), `:timeouts`
  (`%{propose:, prevote:, precommit:, delta:}` em ms), `:clock` (`fn -> segundos end`), `:name`.
  """
  def start_link(opts) do
    {gen, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen)
  end

  @doc "Retrato para testes e para o painel do nó."
  @spec info(GenServer.server()) :: map()
  def info(r), do: GenServer.call(r, :info)

  @doc "Porta de pares."
  @spec port(GenServer.server()) :: non_neg_integer()
  def port(r), do: GenServer.call(r, :port)

  @doc "Pares conectados."
  @spec connected(GenServer.server()) :: [<<_::256>>]
  def connected(r), do: GenServer.call(r, :connected)

  # --- servidor ------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    node = Keyword.fetch!(opts, :node)
    genesis = Keyword.fetch!(opts, :genesis)
    seed = Keyword.fetch!(opts, :seed)
    pub = Ed25519.public_key(seed)
    Process.monitor(node)

    {:ok, guard} = Guard.start_link(sweep_ms: 60_000)

    {:ok, peers} =
      Peers.start_link(
        genesis: genesis,
        seed: seed,
        owner: self(),
        guard: guard,
        port: Keyword.get(opts, :port, 0),
        peers: Keyword.get(opts, :peers, [])
      )

    status = Node.status(node)

    s = %{
      node: node,
      genesis: genesis,
      seed: seed,
      pub: pub,
      validators: genesis.validators,
      peers: peers,
      guard: guard,
      chain_id: status.chain_id,
      height: status.height,
      last_hash: status.last_hash,
      engine: nil,
      wal: nil,
      wal_path: opts |> Keyword.get(:data_dir) |> wal_path(),
      interval: Keyword.get(opts, :interval_ms, 1_000),
      timeouts: Map.merge(@default_timeouts, Keyword.get(opts, :timeouts, %{})),
      clock: Keyword.get(opts, :clock, fn -> System.os_time(:second) end),
      peer_heights: %{},
      syncing: nil,
      start_timer: nil,
      waiting_block: nil,
      evidence: []
    }

    Node.set_tx_hook(node, self())

    case open_wal(s) do
      {:ok, s, journal} -> {:ok, resume(s, journal)}
      {:error, reason} -> {:stop, {:bad_wal, reason}}
    end
  end

  defp wal_path(nil), do: nil
  defp wal_path(dir), do: Path.join(dir, "consensus.wal")

  defp open_wal(%{wal_path: nil} = s), do: {:ok, s, []}

  defp open_wal(s) do
    File.mkdir_p!(Path.dirname(s.wal_path))

    case ConsensusWal.open(s.wal_path, s.height + 1, s.pub, &Block.encode/1, &Block.decode/1) do
      {:ok, wal, journal} -> {:ok, %{s | wal: wal}, journal}
      {:error, _} = err -> err
    end
  end

  # diário com mensagens da altura em curso: retoma exatamente de onde parou
  defp resume(s, []), do: maybe_start(s)

  defp resume(s, journal) do
    Process.put(:valid_cache, %{})
    {engine, actions} = Engine.restore(new_engine(s), journal)
    run_actions(%{s | engine: engine}, actions)
  end

  @impl true
  def handle_call(:info, _from, s) do
    {:reply,
     %{
       height: s.height,
       engine: if(s.engine, do: {s.engine.height, s.engine.round, s.engine.step}),
       peers: Map.keys(s.peer_heights),
       connected: Peers.connected(s.peers),
       evidence: length(s.evidence),
       pending: Node.status(s.node).pending
     }, s}
  end

  def handle_call(:port, _from, s), do: {:reply, Peers.port(s.peers), s}
  def handle_call(:connected, _from, s), do: {:reply, Peers.connected(s.peers), s}

  @impl true
  def handle_info({:brdc_tx, bin}, s) do
    Peers.broadcast(s.peers, {:tx, bin})
    s = retry_block_request(s)
    {:noreply, maybe_start(s)}
  end

  def handle_info({:peer_up, pub}, s) do
    Peers.send_to(s.peers, pub, {:status, s.height, s.last_hash})
    {:noreply, s |> catch_up_peer(pub) |> regossip_pending(pub)}
  end

  def handle_info({:peer_down, pub}, s),
    do: {:noreply, %{s | peer_heights: Map.delete(s.peer_heights, pub)}}

  def handle_info({:peer_msg, from, msg}, s), do: {:noreply, peer_msg(s, from, msg)}

  def handle_info(:start_height, s) do
    s = %{s | start_timer: nil}

    if s.engine == nil and Node.status(s.node).pending > 0,
      do: {:noreply, start_height(s)},
      else: {:noreply, s}
  end

  def handle_info({:timeout, h, step, round}, %{engine: %Engine{height: h}} = s),
    do: {:noreply, feed(s, {:timeout, step, round})}

  def handle_info({:timeout, _, _, _}, s), do: {:noreply, s}

  def handle_info({:sync_timeout, ref}, %{syncing: {_, ref}} = s),
    do: {:noreply, %{s | syncing: nil}}

  def handle_info({:sync_timeout, _}, s), do: {:noreply, s}

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{node: pid} = s),
    do: {:stop, {:node_down, reason}, s}

  def handle_info(_other, s), do: {:noreply, s}

  @impl true
  def terminate(_reason, s) do
    if s.wal, do: ConsensusWal.close(s.wal)
    GenServer.stop(s.peers)
    GenServer.stop(s.guard)
  catch
    :exit, _ -> :ok
  end

  # A fofoca de uma transação sai UMA vez, para quem está conectado naquele instante. Se um par não estava
  # (conexão ainda subindo, queda, partição), ele nunca a receberia, e um proponente sem a transação segura a
  # rodada. Por isso, a quem (re)conecta a réplica reenvia as pendentes (como o mempool do Tendermint); quem já
  # tem responde `:duplicate` e nada se repete. Limitado às mais antigas, para não encher o canal.
  @regossip_max 256

  defp regossip_pending(s, pub) do
    for m <- Node.explorer_mempool(s.node, @regossip_max) do
      Peers.send_to(s.peers, pub, {:tx, Tx.encode(m.tx)})
    end

    s
  end

  # o motor não retransmite: a quem (re)conecta no meio de uma altura, a réplica reenvia o que sabe dela
  # (mensagens assinadas e verificáveis por qualquer um; reentregar é inofensivo)
  defp catch_up_peer(%{engine: nil} = s, _pub), do: s

  defp catch_up_peer(%{engine: engine} = s, pub) do
    for m <- Engine.known_messages(engine) do
      Peers.send_to(
        s.peers,
        pub,
        if(match?(%Proposal{}, m), do: {:proposal, m}, else: {:vote, m})
      )
    end

    s
  end

  # --- início de altura (sem blocos vazios) ------------------------------------------------------

  # há o que fazer e nada em curso: agenda o início depois do agrupamento
  defp maybe_start(%{engine: nil, start_timer: nil} = s) do
    if Node.status(s.node).pending > 0 do
      %{s | start_timer: Process.send_after(self(), :start_height, s.interval)}
    else
      s
    end
  end

  defp maybe_start(s), do: s

  defp start_height(s) do
    Process.put(:valid_cache, %{})
    {engine, actions} = Engine.start(new_engine(s))
    run_actions(%{s | engine: engine}, actions)
  end

  defp new_engine(s) do
    Engine.new(
      chain_id: s.chain_id,
      height: s.height + 1,
      validators: s.validators,
      seed: s.seed,
      hash_fn: &Block.hash/1,
      valid_fn: valid_fn(s)
    )
  end

  # a conferência do bloco (executa tudo) é cara e o motor a chama várias vezes: guarda o resultado por hash
  defp valid_fn(s) do
    node = s.node
    clock = s.clock

    fn block ->
      hash = Block.hash(block)
      cache = Process.get(:valid_cache, %{})

      case Map.fetch(cache, hash) do
        {:ok, v} ->
          v

        :error ->
          v = Node.check_block(node, block, clock.()) == :ok
          Process.put(:valid_cache, Map.put(cache, hash, v))
          v
      end
    end
  end

  # --- motor: eventos e ações ----------------------------------------------------------------------

  defp feed(%{engine: nil} = s, _event), do: s

  defp feed(s, event) do
    {engine, actions} = Engine.handle(s.engine, event)
    run_actions(%{s | engine: engine}, actions)
  end

  # 1) grava no diário o que é nosso, 2) só então executa as ações (transmitir, prazos, decidir)
  defp run_actions(s, actions) do
    if persist(s, actions) == :ok do
      Enum.reduce(actions, s, &do_action/2)
    else
      raise "diário do consenso falhou: nada foi transmitido (falha fechada)"
    end
  end

  defp persist(%{wal: nil}, _actions), do: :ok
  defp persist(%{wal: wal}, actions), do: ConsensusWal.persist_own(wal, actions)

  defp do_action({:broadcast, msg}, s) do
    wire = if match?(%Proposal{}, msg), do: {:proposal, msg}, else: {:vote, msg}
    Peers.broadcast(s.peers, wire)
    s
  end

  defp do_action({:schedule_timeout, step, round}, s) do
    ms = Map.fetch!(s.timeouts, step) + s.timeouts.delta * round
    Process.send_after(self(), {:timeout, s.height + 1, step, round}, ms)
    s
  end

  defp do_action({:need_block, round}, s) do
    case Node.build_proposal(s.node) do
      {:ok, block} -> feed(%{s | waiting_block: nil}, {:block, block})
      # nada para propor agora: espera uma transação chegar (ou o prazo da rodada passar)
      :nothing -> %{s | waiting_block: round}
    end
  end

  defp do_action({:decide, block, cert}, s), do: decided(s, block, cert)

  defp do_action({:evidence, {a, b}}, s) do
    Logger.warning("equivocação de #{Base.encode16(a.voter, case: :lower)} na rodada #{a.round}")
    %{s | evidence: [{a, b} | s.evidence]}
  end

  # chegou transação e éramos o proponente sem nada para propor
  defp retry_block_request(%{engine: %Engine{round: r, step: :propose}, waiting_block: r} = s),
    do: do_action({:need_block, r}, s)

  defp retry_block_request(s), do: s

  # --- decisão ----------------------------------------------------------------------------------------

  defp decided(s, block, cert) do
    case Node.commit_block(s.node, block, cert) do
      {:ok, _h} ->
        Peers.broadcast(s.peers, {:blocks, [{block, cert}]})
        advance(s, block)

      {:error, reason} ->
        raise "não consegui confirmar o bloco decidido #{block.height}: #{inspect(reason)}"
    end
  end

  # depois de confirmar (por decisão ou por sincronização): altura nova, diário vazio, motor parado
  defp advance(s, block) do
    s = %{
      s
      | height: block.height,
        last_hash: Node.status(s.node).last_hash,
        engine: nil,
        waiting_block: nil
    }

    s = if s.wal, do: %{s | wal: reset_wal(s.wal)}, else: s
    maybe_start(s)
  end

  defp reset_wal(wal) do
    {:ok, wal} = ConsensusWal.advance(wal)
    wal
  end

  # --- mensagens dos pares ---------------------------------------------------------------------------------

  # transação de um par: o nó a valida; se for nova, o gancho a espalha de volta (duplicada é descartada)
  defp peer_msg(s, _from, {:tx, bin}) do
    _ = Node.submit(s.node, bin)
    s
  end

  defp peer_msg(s, from, {:proposal, %Proposal{height: h} = p}) do
    cond do
      h == s.height + 1 and Address.hash(p.proposer) == p.block.proposer ->
        s |> ensure_started() |> feed({:proposal, p})

      h > s.height + 1 ->
        request_blocks(s, from, h)

      true ->
        s
    end
  end

  defp peer_msg(s, from, {:vote, v}) do
    cond do
      v.height == s.height + 1 -> s |> ensure_started() |> feed({:vote, v})
      v.height > s.height + 1 -> request_blocks(s, from, v.height)
      true -> s
    end
  end

  defp peer_msg(s, from, {:status, height, _last}) do
    s = %{s | peer_heights: Map.put(s.peer_heights, from, height)}
    if height > s.height, do: request_blocks(s, from, height), else: s
  end

  defp peer_msg(s, from, {:get_blocks, start, max}) do
    list =
      s.node
      |> Node.blocks_from(start, min(max, @sync_batch))
      |> Enum.filter(fn {_b, cert} -> cert != nil end)
      |> fit_frame()

    if list != [], do: Peers.send_to(s.peers, from, {:blocks, list})
    s
  end

  defp peer_msg(s, from, {:blocks, list}), do: apply_blocks(s, from, list)

  # mensagem de consenso da altura em curso com a réplica parada: começa agora
  defp ensure_started(%{engine: nil} = s) do
    if s.start_timer, do: Process.cancel_timer(s.start_timer)
    start_height(%{s | start_timer: nil})
  end

  defp ensure_started(s), do: s

  # --- sincronização ----------------------------------------------------------------------------------

  defp request_blocks(%{syncing: nil} = s, peer, their_height) when their_height > s.height do
    ref = make_ref()
    Process.send_after(self(), {:sync_timeout, ref}, @sync_timeout)
    Peers.send_to(s.peers, peer, {:get_blocks, s.height + 1, @sync_batch})
    %{s | syncing: {peer, ref}}
  end

  defp request_blocks(s, _peer, _h), do: s

  # aplica na ordem; para no primeiro que não confere (certificado ou execução) e desconecta o par
  defp apply_blocks(s, from, list) do
    {s, outcome} = Enum.reduce_while(list, {%{s | syncing: nil}, :ok}, &apply_one/2)

    case outcome do
      :bad ->
        Logger.warning(
          "par #{Base.encode16(binary_part(from, 0, 4), case: :lower)} mandou bloco inválido: desconectado"
        )

        Peers.kick(s.peers, from)
        s

      _ ->
        # ainda atrás de quem respondeu? pede o próximo lote
        behind = Map.get(s.peer_heights, from, 0)
        if behind > s.height, do: request_blocks(s, from, behind), else: s
    end
  end

  defp apply_one({block, _cert}, {acc, _}) when block.height <= acc.height,
    do: {:cont, {acc, :ok}}

  defp apply_one({block, _cert}, {acc, _}) when block.height != acc.height + 1,
    do: {:halt, {acc, :gap}}

  defp apply_one({block, cert}, {acc, _}) do
    case Node.commit_block(acc.node, block, cert) do
      {:ok, _} -> {:cont, {advance(stop_engine(acc), block), :ok}}
      {:error, _} -> {:halt, {acc, :bad}}
    end
  end

  # o bloco chegou por sincronização: a altura em curso (se havia) já foi decidida por outros
  defp stop_engine(s), do: %{s | engine: nil}

  # respeita o tamanho do quadro: manda o que couber (no mínimo um bloco)
  defp fit_frame(list) do
    {kept, _} =
      Enum.reduce_while(list, {[], 0}, fn {b, c} = pair, {acc, size} ->
        n = byte_size(Block.encode(b)) + byte_size(BrdcConsensus.Certificate.encode(c))

        if acc != [] and size + n > @max_reply_bytes,
          do: {:halt, {acc, size}},
          else: {:cont, {acc ++ [pair], size + n}}
      end)

    kept
  end
end
