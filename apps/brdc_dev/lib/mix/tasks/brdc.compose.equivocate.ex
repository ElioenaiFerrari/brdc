defmodule Mix.Tasks.Brdc.Compose.Equivocate do
  @shortdoc "SIMULA um validador do laboratório Docker que equivoca e confere a detecção"
  @moduledoc """
  Para o último validador do laboratório, sobe no lugar dele (mesmo nome na rede e mesma semente) o container
  `equivocator`, que assina **dois votos conflitantes**; o veredito (todos os honestos detectaram?) vem do próprio
  container. Depois confere pelo computador se a rede **continua viva** (uma emissão de teste ainda vira bloco) e
  religa o validador verdadeiro.

      mix brdc.compose.equivocate [--dir compose]

  É **detecção**, não punição (docs/flows/23-equivocation.md). Precisa do laboratório no ar com 4 ou mais
  validadores (`mix brdc.compose.up`). Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.{Compose, Devnet, Equivocation, Net}

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])
    Mix.Task.run("app.config")
    dir = opts[:dir] || Compose.default_dir()

    cfg =
      Compose.read_config(dir) ||
        Mix.raise("laboratório não criado: rode `mix brdc.compose.init`")

    check!(cfg)

    k = cfg.validators
    honest = Enum.to_list(1..(k - 1))
    file = Compose.compose_file(dir)
    ensure_up!(cfg, honest)

    {:ok, devnet} = Devnet.ensure(Path.join(dir, "net"))
    Mix.shell().info("parando v#{k} e subindo o equivocador no lugar dele…")
    docker(file, ["stop", "v#{k}"])

    code = docker_run(file)
    endpoints = for j <- honest, do: {~c"127.0.0.1", Compose.client_port(cfg, j)}
    alive? = Equivocation.alive_after?(hd(endpoints), devnet, endpoints)

    Mix.shell().info("religando v#{k}…")
    docker(file, ["start", "v#{k}"])

    Net.wait_until(
      fn -> match?({_, {:ok, _}}, List.keyfind(Compose.status(cfg), k, 0)) end,
      60_000
    )

    verdict(code, alive?)
  end

  defp check!(cfg) do
    if cfg.validators < 4,
      do:
        Mix.raise("o BFT só tolera um bizantino com 4 ou mais validadores (há #{cfg.validators})")

    System.find_executable("docker") ||
      Mix.raise("o Docker não está instalado ou não está no PATH")
  end

  defp ensure_up!(cfg, honest) do
    down = for {i, {:error, _}} <- Compose.status(cfg), i in honest, do: i

    if down != [],
      do:
        Mix.raise(
          "estes validadores honestos não estão no ar: #{inspect(down)} (`mix brdc.compose.up`)"
        )
  end

  defp verdict(0, true),
    do:
      Mix.shell().info(
        "OK: equivocação DETECTADA por todos os honestos e a rede seguiu viva (só detecção: não há punição)"
      )

  defp verdict(0, false), do: Mix.raise("FALHOU: a rede parou depois da equivocação")

  defp verdict(code, _alive?),
    do: Mix.raise("FALHOU: o equivocador não viu todos os honestos detectarem (código #{code})")

  defp docker(file, args),
    do:
      System.cmd("docker", ["compose", "-f", file] ++ args,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

  # `--build`: usa o código atual; `--use-aliases`: responde pelo nome do validador parado
  defp docker_run(file) do
    {_, code} =
      System.cmd(
        "docker",
        [
          "compose",
          "-f",
          file,
          "--profile",
          "byzantine",
          "run",
          "--rm",
          "--build",
          "--use-aliases",
          "equivocator"
        ],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    code
  end
end
