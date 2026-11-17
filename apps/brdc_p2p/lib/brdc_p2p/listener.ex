defmodule BrdcP2p.Listener do
  @moduledoc """
  Porta de pares (Fase 4): aceita conexões, aplica `BrdcP2p.Guard` e entrega cada par autenticado
  ao `handler` numa tarefa própria (supervisionada). Ordem de cada conexão:

  1. aceita o TCP e **admite o IP** (banimento, teto total e por IP) **antes** do handshake;
  2. handshake TLS com chave fixada + `hello` (`Channel.upgrade/3`); falha vira ponto para o IP;
  3. associa a **chave** do validador (banimento e teto por chave);
  4. chama `handler.(session)`; ao terminar, fecha e libera a vaga, mesmo se o handler falhar.
  """
  use GenServer
  alias BrdcP2p.{Channel, Guard, Session}

  @doc """
  Opções: `:config` (ver `BrdcP2p.Channel`), `:guard` (pid/nome do `Guard`), `:handler`
  (`fn session -> ... end`), `:port` (0 = livre), `:session_opts` (taxa e rajada), `:timeout`.
  """
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Porta em que o listener ficou."
  @spec port(GenServer.server()) :: non_neg_integer()
  def port(l), do: GenServer.call(l, :port)

  @doc "Para de aceitar conexões."
  def stop(l), do: GenServer.stop(l)

  @impl true
  def init(opts) do
    cfg = Keyword.fetch!(opts, :config)
    {:ok, listener} = Channel.listen(cfg, port: Keyword.get(opts, :port, 0))
    {:ok, sup} = Task.Supervisor.start_link()

    ctx = %{
      cfg: cfg,
      guard: Keyword.fetch!(opts, :guard),
      handler: Keyword.fetch!(opts, :handler),
      opts: opts,
      sup: sup
    }

    acceptor = spawn_link(fn -> accept_loop(listener, ctx) end)
    {:ok, %{listener: listener, acceptor: acceptor, port: Channel.port(listener)}}
  end

  @impl true
  def handle_call(:port, _from, s), do: {:reply, s.port, s}

  @impl true
  def terminate(_reason, s), do: :ssl.close(s.listener)

  # --- aceitação ----------------------------------------------------------------------

  defp accept_loop(listener, ctx) do
    case Channel.accept_transport(listener, 1_000) do
      {:ok, transport} ->
        {:ok, pid} =
          Task.Supervisor.start_child(ctx.sup, fn -> wait_then_serve(transport, ctx) end)

        :ssl.controlling_process(transport, pid)
        send(pid, :go)
        accept_loop(listener, ctx)

      {:error, :closed} ->
        :ok

      {:error, _} ->
        accept_loop(listener, ctx)
    end
  end

  defp wait_then_serve(transport, ctx) do
    receive do
      :go -> serve(transport, ctx)
    after
      5_000 -> :ssl.close(transport)
    end
  end

  defp serve(transport, ctx) do
    with {:ok, {ip, _}} <- :ssl.peername(transport),
         {:ok, id} <- Guard.admit(ctx.guard, ip) do
      upgrade_and_run(transport, ip, id, ctx)
    else
      _ -> :ssl.close(transport)
    end
  end

  defp upgrade_and_run(transport, ip, id, ctx) do
    timeout = Keyword.get(ctx.opts, :timeout, 5_000)

    case Channel.upgrade(transport, ctx.cfg, timeout: timeout) do
      {:ok, conn} ->
        run(conn, id, ctx)

      {:error, reason} ->
        Guard.penalize_ip(ctx.guard, ip, offense(reason))
        Guard.release(ctx.guard, id)
        :ssl.close(transport)
    end
  end

  defp run(conn, id, ctx) do
    case Guard.bind_key(ctx.guard, id, conn.peer) do
      :ok ->
        session = Session.new(conn, id, ctx.guard, Keyword.get(ctx.opts, :session_opts, []))

        try do
          ctx.handler.(session)
        after
          Session.close(session)
        end

      {:error, _} ->
        Channel.close(conn)
        Guard.release(ctx.guard, id)
    end
  end

  defp offense(reason) when reason in [:wrong_network, :bad_hello, :bad_peer_cert], do: :bad_hello
  defp offense(_), do: :handshake_failure
end
