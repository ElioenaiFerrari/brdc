defmodule Mix.Tasks.Brdc.Node do
  @shortdoc "Roda UM validador da rede de teste em primeiro plano"
  @moduledoc """
  Roda o validador `K` da rede de teste (nó, réplica BFT, porta de pares e porta pública) no processo atual,
  até você interromper. Normalmente quem chama é `mix brdc.devnet.up`, em segundo plano; rodar à mão serve
  para ver o log ao vivo.

      mix brdc.node --index K [--dir net] [--interval 1s]

  Escuta pares em `peer_base + K - 1` e clientes em `public_base + K - 1` (`net/devnet.json`). Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.{Devnet, Net}
  alias BrdcNode.{Handler, Node, Replica}
  alias BrdcP2p.{Guard, PublicPort}

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [index: :integer, dir: :string, interval: :string])

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:brdc_node)

    dir = Net.dir(opts)

    cfg =
      Net.read_config(dir) || Mix.raise("rede não criada: rode `mix brdc.devnet.init` (ou `up`)")

    i = opts[:index] || Mix.raise("uso: mix brdc.node --index K")
    if i not in 1..cfg.validators, do: Mix.raise("validador #{i} fora de 1..#{cfg.validators}")

    {:ok, %{genesis: genesis, seeds: seeds}} = Devnet.ensure(dir)
    interval = interval(opts[:interval])
    seed = Map.fetch!(seeds, "v#{i}")
    data = Net.data_dir(dir, i)
    File.mkdir_p!(data)

    peers =
      for j <- 1..cfg.validators, j != i do
        %{pub: Enum.at(genesis.validators, j - 1), host: "127.0.0.1", port: Net.peer_port(cfg, j)}
      end

    {:ok, node} =
      Node.start_link(genesis: genesis, seed: seed, block_interval_ms: :manual, data_dir: data)

    {:ok, replica} =
      Replica.start_link(
        node: node,
        genesis: genesis,
        seed: seed,
        data_dir: data,
        port: Net.peer_port(cfg, i),
        peers: peers,
        interval_ms: interval
      )

    {:ok, guard} = Guard.start_link(sweep_ms: 60_000)

    {:ok, port} =
      PublicPort.start_link(
        guard: guard,
        handler: Handler.fun(node, replica: replica),
        port: Net.public_port(cfg, i)
      )

    Mix.shell().info(
      "validador #{i} de #{cfg.validators} pronto: pares :#{Replica.port(replica)}, clientes :#{PublicPort.port(port)}, dados #{data}"
    )

    Process.sleep(:infinity)
  end

  defp interval(nil), do: 1_000

  defp interval(text) do
    case Net.parse_duration(text) do
      {:ok, ms} -> ms
      :error -> Mix.raise("--interval inválido: #{text} (exemplos: 500ms, 1s)")
    end
  end
end
