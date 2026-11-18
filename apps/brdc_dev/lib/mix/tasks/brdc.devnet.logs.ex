defmodule Mix.Tasks.Brdc.Devnet.Logs do
  @shortdoc "Mostra o log de um validador"
  @moduledoc """
  Mostra o final do log de um validador (padrão: o 1).

      mix brdc.devnet.logs [N] [--lines 50] [--follow] [--dir net]

  `--follow` fica acompanhando até você interromper (Ctrl+C).
  """
  use Mix.Task
  alias BrdcDev.Net

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)

    {opts, rest, _} =
      OptionParser.parse(args, strict: [lines: :integer, follow: :boolean, dir: :string])

    dir = Net.dir(opts)
    cfg = Net.read_config(dir) || Mix.raise("nenhuma rede criada em #{dir}")
    i = index(rest, cfg.validators)
    log = Net.log_path(dir, i)
    if not File.exists?(log), do: Mix.raise("v#{i} ainda não tem log (nunca subiu): #{log}")

    lines = opts[:lines] || 50
    args = ["-n", Integer.to_string(lines)] ++ if(opts[:follow], do: ["-f"], else: [])
    System.cmd("tail", args ++ [log], into: IO.stream(:stdio, :line))
    :ok
  end

  defp index([], _max), do: 1

  defp index([n], max) do
    case Integer.parse(n) do
      {i, ""} when i in 1..max//1 -> i
      _ -> Mix.raise("N deve ser um número de 1 a #{max}")
    end
  end

  defp index(_, _), do: Mix.raise("uso: mix brdc.devnet.logs [N]")
end
