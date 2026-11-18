defmodule BrdcNode.Peers do
  @moduledoc """
  Conexões com os outros validadores (M2), sobre o canal TLS 1.3 mútuo de `BrdcP2p` (ADR-0015).

  - **Uma conexão por par.** Quem tem a chave pública **menor** disca; o outro só aceita. Assim nunca há
    conexão dupla nem disputa sobre qual manter.
  - **Quem entra** é conferido no handshake (a chave precisa estar no conjunto de validadores) e pelo `Guard`
    (tetos, pontos, banimento). Mensagem malformada derruba a sessão e vale ponto.
  - **Cada par tem um processo de escrita**: enviar nunca trava o consenso. Par lento demais (fila grande) é
    desconectado.
  - **Reconecta sozinho** (com espera crescente) quando o par cai ou ainda não subiu.

  O `owner` recebe `{:peer_up, chave}`, `{:peer_down, chave}` e `{:peer_msg, chave, mensagem}` (já decodificada
  por `BrdcNode.Wire`).

  Opções: `:genesis`, `:seed`, `:owner` (pid), `:guard` (pid/nome do `BrdcP2p.Guard`), `:port` (0 = livre),
  `:peers` (lista de `%{pub:, host:, port:}`), `:retry_ms` (padrão 500), `:session_opts` (taxa e rajada por
  sessão; padrão 500 mensagens/s e rajada de 1.000, bem acima do padrão de estranhos).
  """
  use GenServer
  alias BrdcNode.{Genesis, Wire}
  alias BrdcP2p.{Channel, Guard, Listener, Session}

  @max_queue 2_000
  # folga para o tráfego do consenso (votos, propostas, transações): 500 msg/s, rajada de 1.000
  @rate 500
  @burst 1_000

  # --- API ---------------------------------------------------------------------------------

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Porta em que este nó aceita pares."
  @spec port(GenServer.server()) :: non_neg_integer()
  def port(p), do: GenServer.call(p, :port)

  @doc "Chaves dos pares conectados agora."
  @spec connected(GenServer.server()) :: [<<_::256>>]
  def connected(p), do: GenServer.call(p, :connected)

  @doc "Envia a mensagem a **todos** os pares conectados (não bloqueia)."
  @spec broadcast(GenServer.server(), Wire.msg()) :: :ok
  def broadcast(p, msg), do: GenServer.cast(p, {:broadcast, Wire.encode(msg)})

  @doc "Envia a um par (se estiver conectado)."
  @spec send_to(GenServer.server(), <<_::256>>, Wire.msg()) :: :ok
  def send_to(p, pub, msg), do: GenServer.cast(p, {:send_to, pub, Wire.encode(msg)})

  @doc "Desconecta um par agora (por exemplo, por mau comportamento); ele pode reconectar."
  @spec kick(GenServer.server(), <<_::256>>) :: :ok
  def kick(p, pub), do: GenServer.cast(p, {:kick, pub})

  # --- servidor ------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    # os discadores são derrubados com `kill` ao parar: capturar saídas impede que o sinal suba pelos links
    Process.flag(:trap_exit, true)
    genesis = Keyword.fetch!(opts, :genesis)
    seed = Keyword.fetch!(opts, :seed)
    me = BrdcCrypto.Ed25519.public_key(seed)
    cfg = Genesis.channel_config(genesis, seed)
    guard = Keyword.fetch!(opts, :guard)
    session_opts = Keyword.get(opts, :session_opts, rate: @rate, burst: @burst)
    peers = self()

    {:ok, listener} =
      Listener.start_link(
        config: cfg,
        guard: guard,
        port: Keyword.get(opts, :port, 0),
        session_opts: session_opts,
        handler: fn session -> run_session(peers, session) end
      )

    state = %{
      me: me,
      cfg: cfg,
      guard: guard,
      owner: Keyword.fetch!(opts, :owner),
      listener: listener,
      port: Listener.port(listener),
      session_opts: session_opts,
      retry_ms: Keyword.get(opts, :retry_ms, 500),
      sessions: %{},
      dialers: []
    }

    # quem tem a chave menor disca para quem tem a maior
    targets = for p <- Keyword.get(opts, :peers, []), me < p.pub, do: p

    dialers =
      for t <- targets, do: spawn_link(fn -> dial_loop(peers, state, t, state.retry_ms) end)

    {:ok, %{state | dialers: dialers}}
  end

  @impl true
  def handle_call(:port, _from, s), do: {:reply, s.port, s}
  def handle_call(:connected, _from, s), do: {:reply, Map.keys(s.sessions), s}

  # um par novo registra a escrita; se já havia uma sessão (provavelmente morta), a antiga é fechada
  def handle_call({:up, pub, writer}, _from, s) do
    case Map.get(s.sessions, pub) do
      nil -> :ok
      old -> send(old, :stop)
    end

    send(s.owner, {:peer_up, pub})
    {:reply, {:ok, s.owner}, %{s | sessions: Map.put(s.sessions, pub, writer)}}
  end

  @impl true
  def handle_cast({:down, pub, writer}, s) do
    # só vale se for a sessão atual (a antiga que foi trocada não derruba a nova)
    if Map.get(s.sessions, pub) == writer do
      send(s.owner, {:peer_down, pub})
      {:noreply, %{s | sessions: Map.delete(s.sessions, pub)}}
    else
      {:noreply, s}
    end
  end

  def handle_cast({:broadcast, bin}, s) do
    for {_pub, w} <- s.sessions, do: send(w, {:send, bin})
    {:noreply, s}
  end

  def handle_cast({:send_to, pub, bin}, s) do
    case Map.get(s.sessions, pub) do
      nil -> :ok
      w -> send(w, {:send, bin})
    end

    {:noreply, s}
  end

  def handle_cast({:kick, pub}, s) do
    if w = Map.get(s.sessions, pub), do: send(w, :stop)
    {:noreply, s}
  end

  # a saída do listener derruba o Peers (sem porta, não há o que fazer); a dos discadores já é tratada no laço deles
  @impl true
  def handle_info({:EXIT, pid, reason}, %{listener: pid} = s), do: {:stop, reason, s}
  def handle_info({:EXIT, _pid, _reason}, s), do: {:noreply, s}

  @impl true
  def terminate(_reason, s) do
    Enum.each(s.dialers, &Process.exit(&1, :kill))
    for {_pub, w} <- s.sessions, do: send(w, :stop)
    Listener.stop(s.listener)
  catch
    :exit, _ -> :ok
  end

  # --- sessão: escrita e leitura ----------------------------------------------------------------

  @doc false
  # roda no processo que for dono da conexão (tarefa do `Listener` ou o discador); volta quando a sessão acaba
  def run_session(peers, session) do
    pub = Session.peer(session)
    writer = spawn(fn -> writer_loop(session) end)

    case GenServer.call(peers, {:up, pub, writer}) do
      {:ok, owner} ->
        try do
          read_loop(session, owner, pub)
        after
          GenServer.cast(peers, {:down, pub, writer})
          send(writer, :stop)
        end

      _ ->
        send(writer, :stop)
    end
  catch
    # o Peers parou: a sessão simplesmente acaba
    :exit, _ -> :ok
  end

  defp read_loop(session, owner, pub) do
    case Session.recv(session, 5_000) do
      {:ok, bin, session} ->
        case Wire.decode(bin) do
          {:ok, msg} ->
            send(owner, {:peer_msg, pub, msg})
            read_loop(session, owner, pub)

          {:error, :malformed} ->
            Session.malformed(session)
            :malformed
        end

      {:error, :timeout, session} ->
        read_loop(session, owner, pub)

      {:error, reason, _session} ->
        reason
    end
  end

  defp writer_loop(session) do
    receive do
      :stop ->
        BrdcP2p.Channel.close(session.conn)

      {:send, bin} ->
        with {:message_queue_len, n} when n <= @max_queue <-
               Process.info(self(), :message_queue_len),
             :ok <- Session.send(session, bin) do
          writer_loop(session)
        else
          _ -> BrdcP2p.Channel.close(session.conn)
        end
    end
  end

  # --- discagem ---------------------------------------------------------------------------------

  defp dial_loop(peers, st, target, wait) do
    next =
      try do
        case dial(peers, st, target) do
          :connected -> st.retry_ms
          :failed -> min(wait * 2, 5_000)
        end
      catch
        _, _ -> min(wait * 2, 5_000)
      end

    Process.sleep(next)
    dial_loop(peers, st, target, next)
  end

  defp dial(peers, st, %{host: host, port: port, pub: pub}) do
    with {:ok, ip} <- resolve(host),
         {:ok, id} <- Guard.admit(st.guard, ip),
         {:ok, conn} <- connect(st, ip, port, id) do
      serve_dialed(peers, st, conn, id, pub)
    else
      _ -> :failed
    end
  end

  # a chave do outro lado precisa ser a esperada e passar pelo guarda; senão fecha e libera a vaga
  defp serve_dialed(peers, st, conn, id, pub) do
    if conn.peer == pub and Guard.bind_key(st.guard, id, conn.peer) == :ok do
      session = Session.new(conn, id, st.guard, st.session_opts)

      try do
        run_session(peers, session)
      after
        Session.close(session)
      end

      :connected
    else
      Channel.close(conn)
      Guard.release(st.guard, id)
      :failed
    end
  end

  defp connect(st, ip, port, id) do
    case Channel.connect(ip, port, st.cfg) do
      {:ok, conn} ->
        {:ok, conn}

      {:error, reason} ->
        Guard.release(st.guard, id)
        {:error, reason}
    end
  end

  defp resolve(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :inet.getaddr(String.to_charlist(host), :inet)
    end
  end
end
