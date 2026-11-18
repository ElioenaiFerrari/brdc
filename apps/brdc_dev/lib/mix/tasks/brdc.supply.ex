defmodule Mix.Tasks.Brdc.Supply do
  @shortdoc "Mostra a oferta, a reserva atestada e a cobertura"
  @moduledoc """
  Mostra quanto BRDC foi emitido, queimado e circula, o último atestado de reserva e a **cobertura** (reserva
  menos o que circula). A cobertura é só informação: a rede não prova a reserva em reais e não congela nada
  (ADR-0009).

      mix brdc.supply [--port P] [--dir net]
  """
  use Mix.Task
  alias BrdcDev.{Cli, Simulation}
  alias BrdcLedger.Amount
  alias BrdcNode.Client

  @impl Mix.Task
  def run(args) do
    {_opts, _rest, endpoint, _net_dir} = Cli.parse(args, [], @moduledoc, "")
    Cli.ensure_node!(endpoint)
    {:ok, s} = Client.supply(endpoint)

    Mix.shell().info("""
    emitido        #{Amount.full(s.minted)} BRDC
    queimado       #{Amount.full(s.burned)} BRDC
    em circulação  #{Amount.full(s.supply)} BRDC  (= emitido - queimado)
    reserva        #{reserve(s.attestation)}
    cobertura      #{Simulation.coverage(s.coverage)}
    """)
  end

  defp reserve(nil), do: "(nenhum atestado ainda)"
  defp reserve(a), do: "R$ #{Amount.full(a.reserve)}  (atestado nº #{a.seq}, ref #{a.ref})"
end
