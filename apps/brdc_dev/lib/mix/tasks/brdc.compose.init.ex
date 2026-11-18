defmodule Mix.Tasks.Brdc.Compose.Init do
  @shortdoc "Prepara o laboratório Docker (chaves de teste, gênese e docker-compose.yml)"
  @moduledoc """
  Cria a pasta do laboratório Docker (padrão `compose/`, ignorada pelo git): chaves de teste e **gênese** com os
  nomes dos serviços (`v1`, `v2`…) como pares, o `docker-compose.yml` com **recursos limitados**, o `.env` e
  `lab.json`. Nunca sobrescreve chaves nem gênese.

      mix brdc.compose.init [--validators 4] [--wallets 2] [--cpus 0.5] [--memory 384m]
                            [--wallet-memory 256m] [--base-port 4700] [--wallet-port 4100] [--interval 1s]
                            [--dir compose]

  Orçamento padrão: 4 validadores e 2 carteiras = **3 CPUs e 2,0 GB no máximo**. As portas ficam só em
  `127.0.0.1` e são diferentes das da rede local (`4545` e `4000`). O número de validadores é decidido aqui e não
  muda (outro número é outra rede: apague a pasta). Só rede de teste.
  """
  use Mix.Task
  alias BrdcDev.{Compose, Net}

  @switches [
    validators: :integer,
    wallets: :integer,
    cpus: :string,
    memory: :string,
    wallet_memory: :string,
    base_port: :integer,
    wallet_port: :integer,
    interval: :string,
    dir: :string
  ]

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    {opts, _, invalid} = OptionParser.parse(args, strict: @switches)
    if invalid != [], do: Mix.raise("opção inválida: #{inspect(invalid)}")
    Mix.Task.run("app.config")

    dir = opts[:dir] || Compose.default_dir()
    overrides = opts |> Keyword.delete(:dir) |> validate!() |> interval_option()

    case Compose.init(dir, overrides) do
      {:ok, o} ->
        {cpus, _} = Float.parse(o.cpus)
        total = (o.validators + o.wallets) * cpus

        Mix.shell().info("""
        laboratório criado em #{dir}
          #{o.validators} validador(es) e #{o.wallets} carteira(s); até #{Float.round(total, 2)} CPUs no total
          clientes dos validadores: 127.0.0.1:#{o.base_port}..#{o.base_port + o.validators - 1}; carteiras: 127.0.0.1:#{o.wallet_port}..
        suba com `mix brdc.compose.up`\
        """)

      {:error, {:validators_mismatch, n}} ->
        Mix.raise(
          "a gênese em #{dir}/net tem #{n} validadores; o número não muda. Para outro número, derrube " <>
            "(`mix brdc.compose.down --volumes`) e apague #{dir}"
        )

      {:error, reason} ->
        Mix.raise("não consegui preparar o laboratório: #{inspect(reason)}")
    end
  end

  defp validate!(opts) do
    check!(
      opts[:validators],
      1..16,
      "--validators (1 a 16; use 4 ou mais para o BFT tolerar uma falha)"
    )

    check!(opts[:wallets], 0..8, "--wallets (0 a 8)")
    check!(opts[:base_port], 1024..65_000, "--base-port")
    check!(opts[:wallet_port], 1024..65_000, "--wallet-port")
    for key <- [:memory, :wallet_memory], do: memory!(opts[key], key)
    cpus!(opts[:cpus])
    opts
  end

  # `--interval 200ms|1s` vira `interval_ms` (a espera, depois da primeira transação, para agrupar a rajada no bloco;
  # padrão 1 s). Vai para `BRDC_INTERVAL_MS` de cada validador.
  defp interval_option(opts) do
    case Keyword.pop(opts, :interval) do
      {nil, rest} ->
        rest

      {text, rest} ->
        ms =
          case Integer.parse(text) do
            {n, "ms"} when n > 0 -> n
            {n, "s"} when n > 0 -> n * 1_000
            _ -> Mix.raise("--interval inválido: #{text} (exemplos: 200ms, 1s)")
          end

        Keyword.put(rest, :interval_ms, ms)
    end
  end

  defp check!(nil, _range, _name), do: :ok

  defp check!(v, range, name),
    do: if(v in range, do: :ok, else: Mix.raise("valor inválido em #{name}: #{v}"))

  defp memory!(nil, _), do: :ok

  defp memory!(v, key),
    do:
      if(v =~ ~r/\A\d{2,5}[mg]\z/,
        do: :ok,
        else: Mix.raise("--#{key} inválido: #{v} (exemplos: 384m, 1g)")
      )

  defp cpus!(nil), do: :ok

  defp cpus!(v) do
    case Float.parse(v) do
      {f, ""} when f >= 0.1 and f <= 4 -> :ok
      _ -> Mix.raise("--cpus inválido: #{v} (entre 0.1 e 4, ex.: 0.5)")
    end
  end
end
