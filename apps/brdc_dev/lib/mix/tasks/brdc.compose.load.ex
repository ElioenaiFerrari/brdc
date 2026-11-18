defmodule Mix.Tasks.Brdc.Compose.Load do
  @shortdoc "Teste de carga do laboratório Docker: degraus de taxa, latência de confirmação, CPU e throttling"
  @moduledoc """
  Teste de carga **aberto, em degraus**: cada degrau oferece uma taxa fixa de transferências por segundo e mede
  taxa aceita, latência de **confirmação** (envio até o bloco), esvaziamento do que ficou pendente, blocos, CPU,
  **throttling** e memória lidos do cgroup de cada validador, reinícios e OOM. Para no primeiro degrau saturado.

      mix brdc.compose.load [--rates 50,100,200,400] [--step 20s] [--repeat 3] [--senders 8]
                            [--drain 60s] [--warmup 20s] [--no-stop] [--dir compose]

  Precisa do laboratório no ar (`mix brdc.compose.up`). Veja `docs/flows/24-load-test.md` para como ler o resultado.
  Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.{Compose, Devnet, Load, Net}

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    opts = parse_opts(args)
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:brdc_node)

    System.find_executable("docker") ||
      Mix.raise("o Docker não está instalado ou não está no PATH")

    dir = opts[:dir] || Compose.default_dir()

    lab =
      Compose.read_config(dir) ||
        Mix.raise("laboratório não criado: rode `mix brdc.compose.init`")

    plan = build_plan(opts, lab, dir)

    {:ok, events} = Agent.start_link(fn -> [] end)
    watcher = watch_events(events)
    warm_up(plan)

    results = run_steps(plan, plan.rates, events, [])
    Port.close(watcher)
    summary(Enum.reverse(results))
    docker_events(events)
  end

  defp parse_opts(args) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [
          rates: :string,
          repeat: :integer,
          step: :string,
          senders: :integer,
          drain: :string,
          warmup: :string,
          no_stop: :boolean,
          dir: :string
        ]
      )

    if invalid != [], do: Mix.raise("opção inválida: #{inspect(invalid)}")
    opts
  end

  # tudo o que um degrau precisa, num mapa só (contas, leituras do Docker, durações e a lista de taxas já repetida)
  defp build_plan(opts, lab, dir) do
    rates = parse_rates(opts[:rates] || "50,100,200,400")
    senders = opts[:senders] || 8
    eps = for i <- 1..lab.validators, do: {~c"127.0.0.1", Compose.client_port(lab, i)}
    names = for i <- 1..lab.validators, do: "brdc-lab-v#{i}-1"
    Mix.shell().info("preparando #{senders} contas de remetente (financiadas fora da medição)…")
    {:ok, devnet} = Devnet.ensure(Path.join(dir, "net"))

    %{
      ctx: Load.prepare(eps, devnet, senders),
      first_rate: hd(rates),
      rates: Enum.flat_map(rates, &List.duplicate(&1, max(opts[:repeat] || 1, 1))),
      stop: not (opts[:no_stop] || false),
      snap: fn -> read_cgroups(names) end,
      health: fn -> read_health(names) end
    }
    |> Map.merge(durations(opts))
  end

  defp durations(opts) do
    %{
      step_ms: duration!(opts[:step] || "20s"),
      drain_ms: duration!(opts[:drain] || "60s"),
      warmup_ms: duration!(opts[:warmup] || "20s")
    }
  end

  # o aquecimento é na taxa do PRIMEIRO degrau: o primeiro degrau pesado paga alocação de memória e caches, e um
  # aquecimento leve deixava a primeira medição 2 a 3 vezes pior que as seguintes
  defp warm_up(plan) do
    Mix.shell().info(
      "aquecimento: #{plan.first_rate} tx/s por #{div(plan.warmup_ms, 1000)} s (descartado)"
    )

    Load.step(plan.ctx, plan.first_rate, plan.warmup_ms, plan.drain_ms, plan.snap, plan.health)
  end

  # `docker events` em segundo plano: guarda cada `die` (com o código de saída REAL) e cada `oom`. Ler `docker inspect`
  # depois de um reinício engana: ExitCode e OOMKilled passam a ser os do processo NOVO.
  defp watch_events(agent) do
    fmt =
      ~s({{.Action}} {{.Actor.Attributes.name}} exitCode={{index .Actor.Attributes "exitCode"}})

    port =
      Port.open({:spawn_executable, System.find_executable("docker")}, [
        :binary,
        :exit_status,
        args: ["events", "--filter", "event=die", "--filter", "event=oom", "--format", fmt]
      ])

    spawn_link(fn -> pump(port, agent) end)
    port
  end

  defp pump(port, agent) do
    receive do
      {^port, {:data, data}} ->
        stamp = Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")

        lines =
          for l <- String.split(data, "\n", trim: true),
              String.contains?(l, "brdc-lab"),
              do: {stamp, l}

        Agent.update(agent, &(&1 ++ lines))
        pump(port, agent)

      {^port, {:exit_status, _}} ->
        :ok
    after
      60_000 -> pump(port, agent)
    end
  end

  defp docker_events(agent) do
    case Agent.get(agent, & &1) do
      [] ->
        Mix.shell().info("\neventos do Docker (die/oom) durante o teste: nenhum")

      list ->
        Mix.shell().info(
          "\neventos do Docker durante o teste:\n" <>
            Enum.map_join(list, "\n", fn {t, l} -> "  #{t}  #{l}" end)
        )
    end
  end

  defp run_steps(_plan, [], _events, acc), do: acc

  defp run_steps(plan, [rate | rest], events, acc) do
    Mix.shell().info("\n=== degrau: #{rate} tx/s por #{div(plan.step_ms, 1000)} s ===")
    r = Load.step(plan.ctx, rate, plan.step_ms, plan.drain_ms, plan.snap, plan.health)
    print_step(r)
    report_restarts(r)
    docker_events(events)

    if saturated?(r) and plan.stop do
      Mix.shell().info("\nsaturou neste degrau; parando (use --no-stop para continuar).")
      [r | acc]
    else
      Process.sleep(3_000)
      run_steps(plan, rest, events, [r | acc])
    end
  end

  @doc false
  def saturated?(r),
    do:
      r.unconfirmed != 0 or r.drain_s > 15 or r.accepted < 0.95 * r.offered or restarted?(r) != []

  defp restarted?(r) do
    for {name, {before, _, _}} <- r.health_before,
        {after_count, oom, _} = Map.fetch!(r.health_after, name),
        after_count != before or oom == "true",
        do: name
  end

  defp print_step(r) do
    c = r.confirm
    t = r.rtt
    b = r.blocks

    Mix.shell().info("""
    oferecidas #{r.offered} em #{r.duration_s} s; aceitas #{r.accepted} (#{r.accepted_rate}/s); recusadas #{inspect(r.errors)}
    envio (ida e volta ao nó): p50 #{t.p50} ms · p95 #{t.p95} ms · p99 #{t.p99} ms · máx #{t.max} ms
    confirmação (envio até o bloco): p50 #{c.p50} ms · p95 #{c.p95} ms · p99 #{c.p99} ms · máx #{c.max} ms (#{r.confirmed} confirmadas, #{r.unconfirmed} NÃO confirmaram)
    pendentes ao fim do envio: #{r.backlog_after_send}; esvaziou em #{r.drain_s} s
    blocos: #{b.count} (altura #{inspect(r.net.heights, charlists: :as_lists)}), #{b.tx} tx, #{b.per_block} tx/bloco, intervalo médio #{inspect(b.interval_s)} s
    fofoca entre nós neste degrau: #{r.gossip.ok} aceitas, #{r.gossip.duplicate} duplicadas, recusadas #{inspect(r.gossip.rejected)}
    mesma altura e mesmo bloco nos validadores: #{r.net.same?}; evidências de equivocação: #{r.net.evidence}\
    """)

    Mix.shell().info(
      "  validador   CPU (núcleos)  throttle (s)  períodos limitados  memória (pico/limite)  oom"
    )

    for {name, d} <- Enum.sort(r.cgroup) do
      Mix.shell().info(
        "  " <>
          String.pad_trailing(String.replace(name, ["brdc-lab-", "-1"], ""), 12) <>
          String.pad_trailing("#{d.cpu_cores}", 15) <>
          String.pad_trailing("#{d.throttled_s}", 14) <>
          String.pad_trailing("#{d.throttled_pct}%", 20) <>
          String.pad_trailing("#{d.mem_peak_mib}/#{d.mem_max_mib} MiB", 23) <> "#{d.oom_kill}"
      )
    end
  end

  defp report_restarts(r) do
    for name <- restarted?(r) do
      Mix.shell().info(
        "\n!!! #{name} REINICIOU ou foi morto por falta de memória durante o degrau; últimas linhas do log:"
      )

      {out, _} = System.cmd("docker", ["logs", "--tail", "25", name], stderr_to_stdout: true)
      Mix.shell().info(out)
    end
  end

  defp summary(results) do
    Mix.shell().info("\n=========== RESUMO (cada linha é uma repetição) ===========")

    Mix.shell().info(
      "oferecida  aceita/s  confirm p50   confirm p95   esvaziou   tx/bloco  intervalo  CPU máx    throttle"
    )

    Enum.each(results, &Mix.shell().info(summary_row(&1)))

    groups =
      results
      |> Enum.group_by(& &1.rate)
      |> Enum.filter(fn {_, rs} -> length(rs) > 1 end)
      |> Enum.sort()

    if groups != [] do
      Mix.shell().info("\n--- por taxa: mediana [mínimo a máximo] das repetições ---")
      for {rate, rs} <- groups, do: Mix.shell().info(rate_summary(rate, rs))
    end
  end

  defp rate_summary(rate, rs) do
    med = fn f -> rs |> Enum.map(f) |> median() end
    rng = fn f -> {rs |> Enum.map(f) |> Enum.min(), rs |> Enum.map(f) |> Enum.max()} end
    {p50a, p50b} = rng.(& &1.confirm.p50)
    {p95a, p95b} = rng.(& &1.confirm.p95)

    "#{rate}/s  (#{length(rs)} repetições)  confirmação p50 #{med.(& &1.confirm.p50)} ms [#{p50a} a #{p50b}]  " <>
      "p95 #{med.(& &1.confirm.p95)} ms [#{p95a} a #{p95b}]  aceita/s #{med.(& &1.accepted_rate)}  " <>
      "esvaziou #{med.(& &1.drain_s)} s  saturados: #{Enum.count(rs, &saturated?/1)}"
  end

  defp summary_row(r) do
    worst = r.cgroup |> Enum.map(&elem(&1, 1)) |> Enum.max_by(& &1.cpu_cores)

    String.pad_trailing("#{r.rate}/s", 11) <>
      String.pad_trailing("#{r.accepted_rate}", 10) <>
      String.pad_trailing("#{r.confirm.p50} ms", 14) <>
      String.pad_trailing("#{r.confirm.p95} ms", 14) <>
      String.pad_trailing("#{r.drain_s} s", 11) <>
      String.pad_trailing("#{r.blocks.per_block}", 10) <>
      String.pad_trailing("#{inspect(r.blocks.interval_s)} s", 11) <>
      String.pad_trailing("#{worst.cpu_cores}", 11) <>
      "#{worst.throttled_pct}%" <> if(saturated?(r), do: "   <- SATURADO", else: "")
  end

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, div(n, 2)),
      else: Float.round((Enum.at(sorted, div(n, 2) - 1) + Enum.at(sorted, div(n, 2))) / 2, 1)
  end

  # --- leituras do Docker ---------------------------------------------------------------------------

  @cg_cmd "cat /sys/fs/cgroup/cpu.stat; echo MEM $(cat /sys/fs/cgroup/memory.current); echo MAX $(cat /sys/fs/cgroup/memory.max); " <>
            "echo PEAK $(cat /sys/fs/cgroup/memory.peak 2>/dev/null); grep oom_kill /sys/fs/cgroup/memory.events"

  defp read_cgroups(names) do
    names
    |> Task.async_stream(
      fn name ->
        {out, _} =
          System.cmd("docker", ["exec", name, "sh", "-c", @cg_cmd], stderr_to_stdout: true)

        {name, Load.parse_cgroup(out)}
      end,
      timeout: 30_000
    )
    |> Map.new(fn {:ok, kv} -> kv end)
  end

  defp read_health(names) do
    {out, _} =
      System.cmd(
        "docker",
        ["inspect", "-f", "{{.Name}} {{.RestartCount}} {{.State.OOMKilled}} {{.State.Status}}"] ++
          names,
        stderr_to_stdout: true
      )

    for line <- String.split(out, "\n", trim: true),
        [name, restarts, oom, status] <- [String.split(line)],
        into: %{},
        do: {String.trim_leading(name, "/"), {String.to_integer(restarts), oom, status}}
  end

  defp parse_rates(text) do
    for r <- String.split(text, ",", trim: true) do
      case Float.parse(r) do
        {n, ""} when n > 0 -> n
        _ -> Mix.raise("--rates inválido: #{inspect(text)} (exemplo: 25,50,100)")
      end
    end
  end

  defp duration!(text) do
    case Net.parse_duration(text) do
      {:ok, ms} -> ms
      :error -> Mix.raise("duração inválida: #{text} (exemplos: 20s, 500ms)")
    end
  end
end
