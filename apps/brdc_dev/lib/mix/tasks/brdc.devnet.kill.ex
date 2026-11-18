defmodule Mix.Tasks.Brdc.Devnet.Kill do
  @shortdoc "Derruba UM validador de repente (simula uma queda)"
  @moduledoc """
  Mata o validador `N` com `kill -9`, sem aviso, como uma queda de energia. Serve para ver a rede continuar
  com os outros e o validador voltar depois (`mix brdc.devnet.up` religa quem caiu; ele se atualiza sozinho).

      mix brdc.devnet.kill N [--dir net]
  """
  use Mix.Task
  alias BrdcDev.Net

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)
    {opts, rest, _} = OptionParser.parse(args, strict: [dir: :string])
    dir = Net.dir(opts)
    cfg = Net.read_config(dir) || Mix.raise("nenhuma rede criada em #{dir}")

    i =
      case rest do
        [n] -> parse_index(n, cfg.validators)
        _ -> Mix.raise("uso: mix brdc.devnet.kill N")
      end

    case Net.read_pid(dir, i) do
      nil ->
        Mix.shell().info("v#{i} não estava rodando")

      pid ->
        Net.signal(pid, "KILL")
        File.rm(Net.pid_path(dir, i))

        Mix.shell().info(
          "v#{i} (pid #{pid}) derrubado com kill -9; `mix brdc.devnet.up` o religa"
        )
    end
  end

  defp parse_index(text, max) do
    case Integer.parse(text) do
      {n, ""} when n in 1..max//1 -> n
      _ -> Mix.raise("N deve ser um número de 1 a #{max}")
    end
  end
end
