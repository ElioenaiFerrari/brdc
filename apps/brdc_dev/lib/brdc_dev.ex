defmodule BrdcDev do
  @moduledoc """
  Ferramentas SÓ de desenvolvimento (nunca em release): sobe um nó local de um validador junto com o resto
  da umbrella (`iex -S mix phx.server` na raiz) e traz as tarefas `mix brdc.*` para testar à mão.

  O nó local é um **nó de verdade**: a carteira e as tarefas falam com ele **pela porta pública em TCP**,
  nunca por chamada direta de função. Assim a fronteira é a mesma de uma rede de verdade (a carteira é um
  cliente, não um nó) e o mesmo código funciona contra um nó em outra máquina.

  Configuração (`config/dev.exs`): `config :brdc_dev, devnet: true, dir: "net", port: 4545, interval_ms: 1000`.
  """
end
