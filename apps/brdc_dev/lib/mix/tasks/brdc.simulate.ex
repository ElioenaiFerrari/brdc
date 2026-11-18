defmodule Mix.Tasks.Brdc.Simulate do
  @shortdoc "Roda um cenário completo de teste (ex.: a produção da moeda)"
  @moduledoc """
  Roda um cenário de ponta a ponta contra a rede de teste que estiver no ar e **confere as regras no fim**
  (sai com erro se alguma não bater).

      mix brdc.simulate issuance [--port P] [--dir net]

  `issuance`: o ciclo da stablecoin. O banco recebe R$ 1.000 e os emissores atestam a reserva; emitem 1.000 BRDC
  para a Alice; um mint com um só emissor é recusado (2 de 2); a Alice paga 250 à Bob; a Bob resgata 250
  (burn); o banco paga os reais e os emissores reduzem a reserva. Cria as carteiras de teste `sim-alice` e
  `sim-bob`. Precisa da rede no ar (`mix brdc.devnet.up`).
  """
  use Mix.Task
  alias BrdcDev.{Cli, Devnet, Simulation}

  @impl Mix.Task
  def run(args) do
    {_opts, rest, endpoint, net_dir} = Cli.parse(args, [], @moduledoc, "")
    Cli.ensure_node!(endpoint)
    {:ok, devnet} = Devnet.ensure(net_dir)

    case rest do
      ["issuance"] ->
        case Simulation.issuance(endpoint, devnet, net_dir, &Mix.shell().info(&1)) do
          {:ok, _} -> :ok
          {:error, failures} -> Mix.raise("o cenário quebrou #{length(failures)} regra(s)")
        end

      _ ->
        Mix.raise("uso: mix brdc.simulate issuance")
    end
  end
end
