defmodule Mix.Tasks.Brdc.Devnet.Up do
  @shortdoc "Sobe os validadores da rede de teste em segundo plano"
  @moduledoc """
  Sobe, em segundo plano, cada validador da rede de teste num processo próprio (pid em `node.pid`, log em
  `node.log`, na pasta do validador). Se a rede ainda não foi criada, cria com 4 validadores (o mesmo que
  `mix brdc.devnet.init` sem opções). Quem já está rodando é deixado em paz: `up` também **religa** um
  validador que caiu (por exemplo depois de `mix brdc.devnet.kill 2`).

      mix brdc.devnet.up [--interval 1s] [--dir net]

  **Nenhum bloco é produzido sozinho:** a rede só cresce quando há transação; sem nada a fazer, os validadores
  ficam parados. `--interval` é a espera depois da primeira transação, para uma rajada dividir o mesmo bloco
  (padrão 1 s; vale na subida: para mudar, pare antes). A carteira (`mix phx.server`) acha o validador 1 em
  `127.0.0.1:4545`.
  """
  use Mix.Task
  alias BrdcDev.{Devnet, Net}
  alias BrdcNode.Client

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string, interval: :string])
    Mix.Task.run("app.config")
    dir = Net.dir(opts)
    cfg = ensure_network(dir)
    mix = System.find_executable("mix") || Mix.raise("não achei o executável `mix` no PATH")

    to_start = for i <- 1..cfg.validators, not Net.running?(dir, i), do: i
    check_ports!(cfg, to_start)
    Enum.each(to_start, &spawn_validator(mix, dir, &1, opts[:interval]))
    Enum.each(1..cfg.validators, &report(dir, cfg, &1, &1 in to_start))
    Mix.shell().info("`mix brdc.devnet.status` mostra o estado; `mix brdc.devnet.down` para tudo")
  end

  defp report(dir, cfg, i, started?) do
    state = state_text(i, started?, started? and wait_ready(cfg, i))
    pid = Net.read_pid(dir, i) || "?"

    Mix.shell().info(
      "  v#{i}: #{state} (clientes :#{Net.public_port(cfg, i)}, pares :#{Net.peer_port(cfg, i)}, pid #{pid})"
    )
  end

  defp state_text(_i, false, _ready), do: "já estava rodando"
  defp state_text(_i, true, true), do: "subiu"
  defp state_text(i, true, false), do: "NÃO respondeu em 90 s: veja `mix brdc.devnet.logs #{i}`"

  defp ensure_network(dir) do
    case Net.read_config(dir) do
      nil ->
        existing = Devnet.existing_validators(dir)
        n = existing || 4
        cfg = Net.new_config(validators: n)
        {:ok, _} = Devnet.ensure(dir, validators: n)
        :ok = Net.write_config(dir, %{cfg | validators: n})
        Mix.shell().info("rede criada (#{n} validadores)")
        %{cfg | validators: n}

      cfg ->
        cfg
    end
  end

  # um nó antigo (ou outro programa) nas portas atrapalha: avisa antes de subir qualquer coisa
  defp check_ports!(cfg, indexes) do
    busy =
      for i <- indexes,
          port <- [Net.public_port(cfg, i), Net.peer_port(cfg, i)],
          not Net.port_free?(port),
          do: {i, port}

    if busy != [] do
      list = Enum.map_join(busy, ", ", fn {i, p} -> "v#{i} (porta #{p})" end)

      Mix.raise(
        "portas ocupadas: #{list}. Pare o que usa essas portas (talvez um `mix phx.server` antigo) ou use `--public-port` e `--peer-port` em `devnet.init`."
      )
    end
  end

  defp spawn_validator(mix, dir, i, interval) do
    File.mkdir_p!(Net.validator_dir(dir, i))
    log = Net.log_path(dir, i)
    extra = if interval, do: " --interval #{shell_word(interval)}", else: ""

    cmd =
      "exec nohup #{shell_word(mix)} brdc.node --index #{i} --dir #{shell_word(dir)}#{extra} >> #{shell_word(log)} 2>&1 < /dev/null & echo $!"

    {out, 0} = System.cmd("/bin/sh", ["-c", cmd], cd: File.cwd!())
    pid = Net.parse_pid(out) || Mix.raise("não consegui o pid do validador #{i}: #{inspect(out)}")
    File.write!(Net.pid_path(dir, i), pid <> "\n")
  end

  defp wait_ready(cfg, i) do
    Net.wait_until(fn -> match?({:ok, _}, Client.status(Net.endpoint(cfg, i))) end, 90_000)
  end

  # escapa para o shell (aspas simples)
  defp shell_word(text), do: "'" <> String.replace(to_string(text), "'", "'\\''") <> "'"
end
