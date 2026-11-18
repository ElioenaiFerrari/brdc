defmodule Mix.Tasks.Brdc.Burn do
  @shortdoc "SIMULA o resgate: queima BRDC de uma carteira de teste"
  @moduledoc """
  A carteira de teste pede o resgate e os emissores (2 de 2) aprovam a **queima** (burn): o BRDC deixa de
  existir e, na vida real, o banco devolveria os reais. Só desenvolvimento.

      mix brdc.burn CARTEIRA VALOR [--ref REF] [--no-wait] [--port P] [--dir net]

  Só carteira de teste (precisa da chave para assinar): a regra do ledger é que quem queima é o dono da conta.
  Depois do resgate, os emissores devem reduzir o lastro: `mix brdc.reserve NOVO_TOTAL`.
  """
  use Mix.Task
  alias BrdcDev.{Chain, Cli, Devnet, Issuance}
  alias BrdcLedger.Amount

  @impl Mix.Task
  def run(args) do
    {opts, rest, endpoint, net_dir} =
      Cli.parse(args, [ref: :string, no_wait: :boolean], @moduledoc, "")

    [name, value] =
      if match?([_, _], rest), do: rest, else: Mix.raise("uso: mix brdc.burn CARTEIRA VALOR")

    units = Cli.amount!(value)

    wallet =
      case Cli.resolve!(net_dir, name) do
        {:wallet, w} ->
          w

        {:address, _} ->
          Mix.raise("para queimar é preciso uma carteira de teste (com a chave), não um endereço")
      end

    Cli.ensure_node!(endpoint)
    {:ok, devnet} = Devnet.ensure(net_dir)
    ref = opts[:ref] || "dev-burn-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

    case Issuance.burn(endpoint, devnet, wallet.account.seed, units, ref) do
      {:ok, sent} ->
        Mix.shell().info("resgate de #{Amount.full(units)} BRDC enviado (ref #{ref})")

        if !opts[:no_wait] do
          :ok = Chain.await_included(endpoint, sent.sender, sent.nonce)
          {:ok, bal} = Chain.balance(endpoint, sent.sender)
          Mix.shell().info("queimado; saldo agora: #{Amount.full(bal)} BRDC")
        end

      {:error, reason} ->
        Mix.raise("a rede recusou: #{inspect(reason)}")
    end
  end
end
