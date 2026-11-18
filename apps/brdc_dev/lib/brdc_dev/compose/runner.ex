defmodule BrdcDev.Compose.Runner do
  @moduledoc """
  Papel `validator` de um container do laboratório Docker: sobe **um validador** a partir da gênese e da semente
  montadas no container (`BrdcNode.Validator`, o mesmo do `mix brdc.validator`). É filho supervisionado do
  `brdc_dev`: se o validador falhar ao subir, o processo cai com o motivo no log e o Docker o reinicia
  (`restart: unless-stopped`). Só desenvolvimento.
  """
  use GenServer
  require Logger
  alias BrdcNode.Validator

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    # `Validator.start/1` liga (link) nó, réplica e porta ao processo que chama: este.
    case Validator.start(opts) do
      {:ok, v} ->
        Logger.info(
          "validador #{v.index} (#{v.address}) pronto: pares :#{v.peer_port}, clientes :#{v.client_port}, " <>
            "#{length(v.peers)} par(es); hash da gênese #{v.genesis_hash}"
        )

        {:ok, v}

      {:error, reason} ->
        Logger.error("não consegui subir o validador: #{inspect(reason)}")
        {:stop, {:validator_failed, reason}}
    end
  end
end
