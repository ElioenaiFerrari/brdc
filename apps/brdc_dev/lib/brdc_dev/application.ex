defmodule BrdcDev.Application do
  @moduledoc false
  use Application
  alias BrdcDev.Devnet
  alias BrdcNode.{Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:brdc_dev, :devnet, false), do: devnet_children(), else: []

    Supervisor.start_link(children, strategy: :one_for_one, name: BrdcDev.Supervisor)
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
