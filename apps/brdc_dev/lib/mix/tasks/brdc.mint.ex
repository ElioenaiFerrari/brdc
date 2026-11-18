defmodule Mix.Tasks.Brdc.Mint do
  @shortdoc "SIMULA os emissores criando BRDC (mint 2 de 2) para uma carteira"
  @moduledoc """
  Os emissores de TESTE (2 de 2) emitem BRDC para uma carteira de teste ou endereço. É o "depósito foi
  confirmado, emitir". Só desenvolvimento.

      mix brdc.mint QUEM VALOR [--ref REF] [--no-wait] [--port P] [--dir net]

  `QUEM` é o nome de uma carteira de teste ou um endereço `brdc1…`. `VALOR` em BRDC (`100`, `12,5`).
  `--ref` identifica o depósito (cada referência só vale uma vez). Espera o bloco, a menos que `--no-wait`.
  Para registrar o lastro, use `mix brdc.reserve`; para ver a cobertura, `mix brdc.supply`.
  """
  use Mix.Task
  alias BrdcDev.{Chain, Cli, Devnet, Issuance, Wallets}
  alias BrdcLedger.Amount

  @impl Mix.Task
  def run(args) do
    {opts, rest, endpoint, net_dir} =
      Cli.parse(args, [ref: :string, no_wait: :boolean], @moduledoc, "")

    [who, value] =
      if match?([_, _], rest),
        do: rest,
        else: Mix.raise("uso: mix brdc.mint QUEM VALOR [--ref REF]")

    units = Cli.amount!(value)
    target = who |> then(&Cli.resolve!(net_dir, &1)) |> Wallets.hash()
    Cli.ensure_node!(endpoint)
    {:ok, devnet} = Devnet.ensure(net_dir)
    ref = opts[:ref] || "dev-mint-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    case Issuance.mint(endpoint, devnet, target, units, ref) do
      {:ok, sent} ->
        Mix.shell().info("emissão de #{Amount.full(units)} BRDC enviada (ref #{ref})")
        wait(opts, endpoint, sent, target)

      {:error, reason} ->
        Mix.raise("a rede recusou: #{inspect(reason)}")
    end
  end

  defp wait(opts, endpoint, sent, target) do
    if opts[:no_wait] do
      Mix.shell().info("entra no próximo bloco")
    else
      case Chain.await_included(endpoint, sent.sender, sent.nonce) do
        :ok ->
          {:ok, bal} = Chain.balance(endpoint, target)
          Mix.shell().info("incluída no bloco; saldo agora: #{Amount.full(bal)} BRDC")

        {:error, :timeout} ->
          Mix.raise("não entrou em 30 s (a rede está no ar? `mix brdc.devnet.status`)")
      end
    end
  end
end
