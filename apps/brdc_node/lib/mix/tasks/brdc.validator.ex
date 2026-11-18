defmodule Mix.Tasks.Brdc.Validator do
  @shortdoc "Roda UM validador a partir da gênese e da sua semente (rede entre computadores)"
  @moduledoc """
  Roda um validador no processo atual, até você interromper, lendo a gênese (pública) e a semente (privada) de
  arquivos. Serve para rodar a mesma rede em **computadores diferentes** (roteiro em `docs/NETWORKS.md`).

      mix brdc.validator --genesis net/genesis.json --seed net/v1.seed --data net/data-v1 \\
        [--peer-port 4600] [--public-port 4545] [--interval 1s]

  Os pares vêm do `bootstrap` da gênese. Escuta em todas as interfaces: libere só as duas portas no firewall.
  A semente é o validador: **nunca** a copie para outro computador. Só rede de teste.
  """
  use Mix.Task
  alias BrdcNode.Validator

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          genesis: :string,
          seed: :string,
          data: :string,
          peer_port: :integer,
          public_port: :integer,
          interval: :string
        ]
      )

    if "--help" in args or "-h" in args, do: Mix.shell().info(@moduledoc) && exit(:normal)
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:brdc_node)

    genesis = required!(opts, :genesis, "faltou --genesis (caminho do genesis.json)")
    seed = required!(opts, :seed, "faltou --seed (caminho da NOME.seed deste validador)")
    data = required!(opts, :data, "faltou --data (pasta onde guardar os blocos deste validador)")

    result =
      Validator.start(
        genesis: genesis,
        seed: seed,
        data_dir: data,
        peer_port: opts[:peer_port] || 4600,
        public_port: opts[:public_port] || 4545,
        interval_ms: interval(opts[:interval])
      )

    case result do
      {:ok, v} -> announce(v, data)
      {:error, reason} -> Mix.raise(explain(reason, seed))
    end
  end

  defp required!(opts, key, message), do: opts[key] || Mix.raise(message)

  defp announce(v, data) do
    Mix.shell().info(
      "validador #{v.index} (#{v.address}) pronto: pares :#{v.peer_port}, clientes :#{v.client_port}, " <>
        "#{length(v.peers)} par(es) na gênese, dados #{data}\n  hash da gênese: #{v.genesis_hash} " <>
        "(tem de ser IGUAL em todos os computadores)"
    )

    Process.sleep(:infinity)
  end

  defp explain(:not_a_validator, seed),
    do: "a chave de #{seed} não está na lista de validadores desta gênese"

  defp explain({what, path, reason}, _seed),
    do: "não consegui ler #{what} em #{path}: #{inspect(reason)}"

  defp explain(reason, _seed), do: "não consegui subir o validador: #{inspect(reason)}"

  defp interval(nil), do: 1_000

  defp interval(text) do
    case Integer.parse(text) do
      {n, "ms"} when n > 0 -> n
      {n, "s"} when n > 0 -> n * 1_000
      _ -> Mix.raise("--interval inválido: #{text} (exemplos: 500ms, 1s)")
    end
  end
end
