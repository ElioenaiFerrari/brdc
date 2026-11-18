defmodule Mix.Tasks.Brdc.Compose.Down do
  @shortdoc "Derruba o laboratório Docker (com --volumes, apaga também os blocos)"
  @moduledoc """
  Roda `docker compose down`. Sem `--volumes` os blocos de cada validador ficam nos volumes (o próximo `up`
  continua da altura anterior); com `--volumes` tudo é apagado.

      mix brdc.compose.down [--dir compose] [--volumes]
  """
  use Mix.Task
  alias BrdcDev.{Compose, Net}

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string, volumes: :boolean])
    dir = opts[:dir] || Compose.default_dir()
    file = Compose.compose_file(dir)
    File.exists?(file) || Mix.raise("laboratório não criado em #{dir}")

    System.find_executable("docker") ||
      Mix.raise("o Docker não está instalado ou não está no PATH")

    flags = if opts[:volumes], do: ["--volumes"], else: []

    {_, code} =
      System.cmd("docker", ["compose", "-f", file, "down"] ++ flags,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if code != 0, do: Mix.raise("docker compose down falhou (código #{code})")
  end
end
