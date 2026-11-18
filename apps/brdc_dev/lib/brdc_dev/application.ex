defmodule BrdcDev.Application do
  @moduledoc false
  use Application
  alias BrdcDev.{Devnet, Net}
  alias BrdcNode.{Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @impl true
  def start(_type, _args) do
    children = if embed_node?(), do: devnet_children(), else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: BrdcDev.Supervisor)
  end

  # O nó solo embutido só faz sentido numa rede de UM validador que o `phx.server` mesmo criou. Se existe uma rede
  # gerenciada (`mix brdc.devnet.init|up`, com `net/devnet.json`) ou a gênese tem mais de um validador, a carteira
  # conversa com os validadores que já estão rodando (porta pública 4545) e nada é embutido.
  defp embed_node? do
    dir = Application.get_env(:brdc_dev, :dir) || Devnet.default_dir()

    Application.get_env(:brdc_dev, :devnet, false) and Net.read_config(dir) == nil and
      Devnet.existing_validators(dir) in [nil, 1]
  end

  defp devnet_children do
    dir = Application.get_env(:brdc_dev, :dir) || Devnet.default_dir()
    {:ok, %{genesis: genesis, seeds: seeds}} = Devnet.ensure(dir)

    [
      {Node,
       name: BrdcDev.Node,
       genesis: genesis,
       seed: Map.fetch!(seeds, "v1"),
       block_interval_ms: Application.get_env(:brdc_dev, :interval_ms, 1_000),
       data_dir: Application.get_env(:brdc_dev, :data_dir, Path.join(dir, "data"))},
      {Guard, name: BrdcDev.Guard},
      %{
        id: BrdcDev.PublicPort,
        start:
          {PublicPort, :start_link,
           [
             [
               guard: BrdcDev.Guard,
               handler: Handler.fun(BrdcDev.Node),
               port: Application.get_env(:brdc_dev, :port, 4545)
             ]
           ]}
      }
    ]
  end
end
