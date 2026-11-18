defmodule Mix.Tasks.Brdc.Devnet.Reset do
  @shortdoc "Apaga o disco da rede de teste (volta à gênese)"
  @moduledoc """
  Apaga os blocos, os diários do consenso, os pids e os logs da rede de teste, para ela recomeçar da gênese.
  **Não** apaga as chaves nem a gênese, a menos que você peça.

      mix brdc.devnet.reset [--all] [--port 4545] [--dir net]

  `--all` apaga também a gênese e a configuração (`net/genesis.json`, `net/devnet.json`): serve para mudar o
  número de validadores. As chaves de teste continuam. Recusa se houver validador rodando (`mix brdc.devnet.down`
  antes) ou nó respondendo na porta (o `mix phx.server` antigo). Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.Net

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [all: :boolean, port: :integer, dir: :string])
    dir = Net.dir(opts)
    cfg = Net.read_config(dir)
    ensure_stopped!(dir, cfg, opts[:port])

    case Enum.filter(paths(dir, cfg, opts[:all]), &remove/1) do
      [] -> Mix.shell().info("nada a apagar em #{dir}")
      removed -> Enum.each(removed, &Mix.shell().info("apagado: #{&1}"))
    end
  end

  # nada pode estar rodando: nem validador gerenciado, nem um nó respondendo na porta
  defp ensure_stopped!(dir, cfg, port_opt) do
    running = if cfg, do: for(i <- 1..cfg.validators, Net.running?(dir, i), do: i), else: []

    if running != [] do
      Mix.raise(
        "há validador(es) rodando (#{Enum.join(running, ", ")}); rode `mix brdc.devnet.down` antes"
      )
    end

    port = port_opt || (cfg && cfg.public_base) || 4545

    if not Net.port_free?(port) do
      Mix.raise("há um nó respondendo na porta #{port}; pare-o antes de apagar o disco")
    end
  end

  defp paths(dir, cfg, all?) do
    n = if cfg, do: cfg.validators, else: 0

    [Path.join(dir, "data")] ++
      Enum.flat_map(1..max(n, 1)//1, fn i -> if n == 0, do: [], else: validator_paths(dir, i) end) ++
      if(all?, do: [Path.join(dir, "genesis.json"), Net.config_path(dir)], else: [])
  end

  defp validator_paths(dir, i) do
    v = Net.validator_dir(dir, i)

    [Net.data_dir(dir, i), Net.pid_path(dir, i), Net.log_path(dir, i)]
    |> Enum.filter(&String.starts_with?(&1, v))
  end

  defp remove(path) do
    if File.exists?(path) do
      File.rm_rf!(path)
      true
    else
      false
    end
  end
end
