defmodule Mix.Tasks.Brdc.Fund do
  @shortdoc "Atalho de mint: BRDC de TESTE para uma carteira ou endereço"
  @moduledoc """
  Atalho de `mix brdc.mint`: os emissores de TESTE (2 de 2) emitem BRDC.

      mix brdc.fund QUEM VALOR [--port P] [--dir net]

  Veja `mix help brdc.mint` (referência, `--no-wait`) e `mix brdc.supply` (oferta e reserva).
  """
  use Mix.Task
  alias BrdcDev.Net
  alias Mix.Tasks.Brdc.Mint

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    Mint.run(args)
  end
end
