defmodule Mix.Tasks.Brdc.Devnet.Init do
  @shortdoc "Cria a gênese e as chaves da rede de teste (N validadores)"
  @moduledoc """
  Cria as chaves de teste e a gênese da rede local. **Nunca sobrescreve** o que existe.

      mix brdc.devnet.init [--validators N] [--public-port 4545] [--peer-port 4600] [--dir net]

  Padrão: 4 validadores (o mínimo para o BFT tolerar 1 falha). O número de validadores é decidido aqui e não
  muda depois (outro número é outra rede: `mix brdc.devnet.reset --all`). `--solo` é atalho de `--validators 1`.
  Papéis: `v1`…`vN` (validadores), `i1` e `i2` (emissores, 2 de 2), `a1` e `a2` (autoridades raiz, 2 de 2).
  """
  use Mix.Task
  alias BrdcDev.{Devnet, Net}

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)

    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          validators: :integer,
          solo: :boolean,
          public_port: :integer,
          peer_port: :integer,
          dir: :string
        ]
      )

    Mix.Task.run("app.config")
    dir = Net.dir(opts)
    n = if opts[:solo], do: 1, else: opts[:validators] || 4
    if n not in 1..16, do: Mix.raise("--validators deve estar entre 1 e 16")

    File.mkdir_p!(dir)
    decide(dir, opts, n, Devnet.existing_validators(dir), Net.read_config(dir) != nil)
  end

  # o que fazer conforme já exista gênese e configuração da rede gerenciada
  defp decide(dir, opts, n, nil, _managed), do: create(dir, opts, n)

  defp decide(_dir, _opts, n, n, true),
    do: Mix.shell().info("a rede já existe (#{n} validadores); nada a fazer")

  defp decide(_dir, _opts, n, existing, true) do
    Mix.raise(
      "a rede já existe com #{existing} validadores; para #{n}, rode `mix brdc.devnet.reset --all`"
    )
  end

  defp decide(_dir, _opts, _n, existing, false) do
    Mix.raise(
      "já existe uma gênese de #{existing} validador(es) criada pelo `mix phx.server`; " <>
        "para outra, rode `mix brdc.devnet.reset --all`"
    )
  end

  defp create(dir, opts, n) do
    cfg =
      Net.new_config(validators: n, public_port: opts[:public_port], peer_port: opts[:peer_port])

    {:ok, %{genesis: g}} = Devnet.ensure(dir, validators: n)
    :ok = Net.write_config(dir, cfg)
    Mix.shell().info("rede criada em #{dir}: #{n} validador(es), rede #{g.chain_id}")

    for i <- 1..n do
      Mix.shell().info(
        "  v#{i}: pares :#{Net.peer_port(cfg, i)}, clientes :#{Net.public_port(cfg, i)}"
      )
    end

    Mix.shell().info("suba com `mix brdc.devnet.up`")
  end
end
