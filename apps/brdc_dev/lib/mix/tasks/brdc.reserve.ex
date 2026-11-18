defmodule Mix.Tasks.Brdc.Reserve do
  @shortdoc "SIMULA os emissores atestando o lastro em reais"
  @moduledoc """
  Os emissores de TESTE (2 de 2) atestam **quantos reais há em caixa** (o total, não a variação). A rede só
  informa a cobertura (reserva contra o que circula); não prova a reserva real (ADR-0009). Só desenvolvimento.

      mix brdc.reserve TOTAL [--ref REF] [--no-wait] [--port P] [--dir net]

  `TOTAL` em reais (mesma escala do BRDC, 1 BRDC = R$ 1): `mix brdc.reserve 1000`. Cada atestado tem número de
  sequência (1, 2, 3…), escolhido sozinho. Veja o resultado em `mix brdc.supply`.
  """
  use Mix.Task
  alias BrdcDev.{Chain, Cli, Devnet, Issuance}
  alias BrdcLedger.Amount

  @impl Mix.Task
  def run(args) do
    {opts, rest, endpoint, net_dir} =
      Cli.parse(args, [ref: :string, no_wait: :boolean], @moduledoc, "")

    [value] = if match?([_], rest), do: rest, else: Mix.raise("uso: mix brdc.reserve TOTAL")

    units =
      case Amount.parse(value),
        do: (
          {:ok, u} -> u
          :error -> Mix.raise("valor inválido: #{inspect(value)}")
        )

    Cli.ensure_node!(endpoint)
    {:ok, devnet} = Devnet.ensure(net_dir)

    ref =
      opts[:ref] || "dev-reserva-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    case Issuance.attest(endpoint, devnet, units, ref) do
      {:ok, sent} ->
        Mix.shell().info("atestado de reserva de R$ #{Amount.full(units)} enviado (ref #{ref})")
        if !opts[:no_wait], do: :ok = Chain.await_included(endpoint, sent.sender, sent.nonce)
        Mix.shell().info("veja `mix brdc.supply`")

      {:error, reason} ->
        Mix.raise("a rede recusou: #{inspect(reason)}")
    end
  end
end
