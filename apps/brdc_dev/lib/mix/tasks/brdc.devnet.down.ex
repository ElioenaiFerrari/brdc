defmodule Mix.Tasks.Brdc.Devnet.Down do
  @shortdoc "Para os validadores da rede de teste"
  @moduledoc """
  Para todos os validadores em segundo plano (pede para terminar e, se não terminarem em 10 s, força). Os blocos
  ficam em disco: ao subir de novo, a rede continua de onde parou.

      mix brdc.devnet.down [--dir net]
  """
  use Mix.Task
  alias BrdcDev.Net

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])
    dir = Net.dir(opts)
    cfg = Net.read_config(dir)

    if cfg == nil do
      Mix.shell().info("nenhuma rede criada em #{dir}")
    else
      for i <- 1..cfg.validators, do: stop(dir, i)
    end
  end

  defp stop(dir, i) do
    pid = Net.read_pid(dir, i)

    cond do
      pid == nil ->
        Mix.shell().info("  v#{i}: não estava rodando")

      not Net.alive?(pid) ->
        File.rm(Net.pid_path(dir, i))
        Mix.shell().info("  v#{i}: já tinha parado (pid velho removido)")

      true ->
        Mix.shell().info("  v#{i}: #{terminate(pid)}")
        File.rm(Net.pid_path(dir, i))
    end
  end

  # pede para terminar; se não obedecer em 10 s, força
  defp terminate(pid) do
    Net.signal(pid, "TERM")

    if Net.wait_until(fn -> not Net.alive?(pid) end, 10_000) do
      "parou"
    else
      Net.signal(pid, "KILL")
      "não obedeceu em 10 s, foi forçado"
    end
  end
end
