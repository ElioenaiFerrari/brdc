defmodule Mix.Tasks.Brdc.Compose.Up do
  @shortdoc "Sobe o laboratório Docker (build, validadores e carteiras) e espera a rede andar"
  @moduledoc """
  Roda `docker compose up -d --build` com o compose gerado por `mix brdc.compose.init` e espera os validadores
  responderem (até 120 s). A primeira vez demora (build da imagem); as seguintes usam o cache.

      mix brdc.compose.up [--dir compose] [--no-build]
  """
  use Mix.Task
  alias BrdcDev.{Compose, Net}
  alias Mix.Tasks.Brdc.Compose.Status

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string, no_build: :boolean])
    Mix.Task.run("app.config")
    dir = opts[:dir] || Compose.default_dir()

    cfg =
      Compose.read_config(dir) ||
        Mix.raise("laboratório não criado: rode `mix brdc.compose.init`")

    build = if opts[:no_build], do: [], else: ["--build"]
    docker!(["compose", "-f", Compose.compose_file(dir), "up", "-d"] ++ build)

    Mix.shell().info("esperando os #{cfg.validators} validadores…")

    if Net.wait_until(
         fn -> Enum.all?(Compose.status(cfg), &match?({_, {:ok, _}}, &1)) end,
         120_000
       ) do
      Status.print(cfg)
    else
      Mix.raise(
        "os validadores não responderam em 120 s; veja `docker compose -f #{Compose.compose_file(dir)} logs`"
      )
    end
  end

  defp docker!(args) do
    System.find_executable("docker") ||
      Mix.raise("o Docker não está instalado ou não está no PATH")

    case System.cmd("docker", args, into: IO.stream(:stdio, :line), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("docker #{Enum.join(args, " ")} falhou (código #{code})")
    end
  end
end
