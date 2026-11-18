defmodule Mix.Tasks.Brdc.Devnet.Equivocate do
  @shortdoc "SIMULA um validador que equivoca (assina dois votos conflitantes) e confere a detecção"
  @moduledoc """
  Derruba o validador `K` (padrão: o último), entra na rede com a **identidade dele** e assina **dois votos
  conflitantes** (mesmo tipo, altura e rodada, blocos diferentes), o pior comportamento de um validador no BFT.
  Confere então se **todos os honestos detectaram** (contador de evidências, `mix brdc.compose.status` mostra a
  mesma coluna) e se a rede **continua viva** (uma emissão de teste ainda vira bloco). No fim religa o validador.

      mix brdc.devnet.equivocate [--victim K] [--duration 15s] [--dir net]

  É **detecção**, não punição: não há stake nem corte (docs/flows/23-equivocation.md). Precisa da rede de teste no
  ar com 4 ou mais validadores (`mix brdc.devnet.up`). Só desenvolvimento.
  """
  use Mix.Task
  alias BrdcDev.{Devnet, Equivocation, Net}

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)

    {opts, _, _} =
      OptionParser.parse(args, strict: [dir: :string, victim: :integer, duration: :string])

    Mix.Task.run("app.config")
    dir = Net.dir(opts)

    cfg =
      Net.read_config(dir) ||
        Mix.raise("nenhuma rede criada em #{dir}: rode `mix brdc.devnet.up`")

    if cfg.validators < 4,
      do:
        Mix.raise(
          "o BFT só tolera um bizantino com 4 ou mais validadores (esta rede tem #{cfg.validators})"
        )

    k = opts[:victim] || cfg.validators
    if k not in 1..cfg.validators, do: Mix.raise("--victim deve ser de 1 a #{cfg.validators}")
    honest = Enum.reject(1..cfg.validators, &(&1 == k))
    stopped = for j <- honest, not Net.running?(dir, j), do: j

    if stopped != [],
      do:
        Mix.raise(
          "estes validadores honestos não estão no ar: #{inspect(stopped)} (`mix brdc.devnet.up`)"
        )

    {:ok, devnet} = Devnet.ensure(dir)
    Mix.Task.rerun("brdc.devnet.kill", [Integer.to_string(k), "--dir", dir])

    result = attack(dir, cfg, devnet, k, honest, duration(opts[:duration]))
    Mix.Task.rerun("brdc.devnet.up", ["--dir", dir])
    finish(result)
  end

  defp attack(dir, cfg, devnet, k, honest, duration_ms) do
    endpoints = for j <- honest, do: {~c"127.0.0.1", Net.public_port(cfg, j)}

    peers =
      for j <- honest,
          do: %{
            pub: Enum.at(devnet.genesis.validators, j - 1),
            host: "127.0.0.1",
            port: Net.peer_port(cfg, j)
          }

    Mix.shell().info(
      "v#{k} derrubado; entrando como ele e equivocando por até #{div(duration_ms, 1000)} s…"
    )

    with {:ok, report} <-
           Equivocation.run(
             genesis: Path.join(dir, "genesis.json"),
             seed: Path.join(dir, "v#{k}.seed"),
             endpoints: endpoints,
             peers: peers,
             peer_port: Net.peer_port(cfg, k),
             duration_ms: duration_ms
           ) do
      for line <- Equivocation.describe(report), do: Mix.shell().info(line)
      {:ok, report, Equivocation.alive_after?(hd(endpoints), devnet, endpoints)}
    end
  end

  defp finish({:ok, report, alive?}) do
    Mix.shell().info(
      if(alive?,
        do: "a rede continuou viva: a emissão de teste virou bloco nos honestos",
        else: "A REDE NÃO PRODUZIU BLOCO depois do voto duplo"
      )
    )

    cond do
      not report.passed ->
        Mix.raise("FALHOU: nem todos os honestos detectaram a equivocação")

      not alive? ->
        Mix.raise("FALHOU: a rede parou depois da equivocação")

      true ->
        Mix.shell().info(
          "OK: equivocação DETECTADA por todos os honestos e a rede seguiu viva (só detecção: não há punição)"
        )
    end
  end

  defp finish({:error, reason}), do: Mix.raise("não consegui simular: #{inspect(reason)}")

  defp duration(nil), do: 15_000

  defp duration(text) do
    case Net.parse_duration(text) do
      {:ok, ms} -> ms
      :error -> Mix.raise("--duration inválido: #{text} (exemplos: 10s, 500ms)")
    end
  end
end
