defmodule BrdcP2p.Guard do
  @moduledoc """
  Processo que guarda o estado de `BrdcP2p.Limits` e o relógio (borda de I/O da política pura).
  Um por nó. Todas as decisões vêm de `Limits`; aqui só serializamos o acesso e fornecemos o tempo.
  """
  use GenServer
  alias BrdcP2p.Limits

  def start_link(opts \\ []) do
    {gen_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Admite uma conexão do IP."
  def admit(g, ip), do: GenServer.call(g, {:admit, ip})
  @doc "Associa a conexão à chave do validador."
  def bind_key(g, id, key), do: GenServer.call(g, {:bind_key, id, key})
  @doc "Libera a conexão."
  def release(g, id), do: GenServer.call(g, {:release, id})
  @doc "Registra uma ofensa da conexão."
  def penalize(g, id, reason), do: GenServer.call(g, {:penalize, id, reason})
  @doc "Registra uma ofensa de um IP sem conexão admitida."
  def penalize_ip(g, ip, reason), do: GenServer.call(g, {:penalize_ip, ip, reason})
  @doc "Estado atual (para testes e painel)."
  def state(g), do: GenServer.call(g, :state)
  @doc "Relógio atual do guarda (ms)."
  def now(g), do: GenServer.call(g, :now)

  @impl true
  def init(opts) do
    {clock, limit_opts} = Keyword.pop(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {sweep, limit_opts} = Keyword.pop(limit_opts, :sweep_ms, 60_000)
    if sweep != :never, do: Process.send_after(self(), :sweep, sweep)
    {:ok, %{limits: Limits.new(limit_opts), clock: clock, sweep: sweep}}
  end

  @impl true
  def handle_call({:admit, ip}, _from, s) do
    case Limits.admit(s.limits, ip, s.clock.()) do
      {:ok, id, l} -> {:reply, {:ok, id}, %{s | limits: l}}
      {:error, _} = e -> {:reply, e, s}
    end
  end

  def handle_call({:bind_key, id, key}, _from, s) do
    case Limits.bind_key(s.limits, id, key, s.clock.()) do
      {:ok, l} -> {:reply, :ok, %{s | limits: l}}
      {:error, _} = e -> {:reply, e, s}
    end
  end

  def handle_call({:release, id}, _from, s),
    do: {:reply, :ok, %{s | limits: Limits.release(s.limits, id)}}

  def handle_call({:penalize, id, reason}, _from, s) do
    {status, l} = Limits.penalize(s.limits, id, reason, s.clock.())
    {:reply, status, %{s | limits: l}}
  end

  def handle_call({:penalize_ip, ip, reason}, _from, s) do
    {status, l} = Limits.penalize_ip(s.limits, ip, reason, s.clock.())
    {:reply, status, %{s | limits: l}}
  end

  def handle_call(:state, _from, s), do: {:reply, s.limits, s}
  def handle_call(:now, _from, s), do: {:reply, s.clock.(), s}

  @impl true
  def handle_info(:sweep, s) do
    Process.send_after(self(), :sweep, s.sweep)
    {:noreply, %{s | limits: Limits.sweep(s.limits, s.clock.())}}
  end
end
