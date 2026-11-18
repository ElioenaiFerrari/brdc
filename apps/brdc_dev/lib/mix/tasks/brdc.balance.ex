defmodule Mix.Tasks.Brdc.Balance do
  @shortdoc "Mostra o saldo de um endereço no nó local"
  @moduledoc """
  Consulta o nó pela porta pública (não confia nele: por ora só lê).

      mix brdc.balance brdc1… [--port 4545]
  """
  use Mix.Task
  alias BrdcLedger.Amount
  alias BrdcNode.Client

  @impl Mix.Task
  def run(args) do
    {_opts, rest, endpoint, net_dir} = BrdcDev.Cli.parse(args, [], @moduledoc, "")

    with [who] <- rest,
         hash = who |> then(&BrdcDev.Cli.resolve!(net_dir, &1)) |> BrdcDev.Wallets.hash(),
         {:ok, status} <- Client.status(endpoint),
         {:ok, acc} <- Client.account(endpoint, hash) do
      Mix.shell().info(
        "rede: #{status.chain_id} · altura #{status.height} · pendentes #{status.pending}"
      )

      Mix.shell().info("saldo: #{Amount.full(acc.balance)} BRDC (nonce #{acc.nonce})")

      if acc.pending_balance != acc.balance,
        do: Mix.shell().info("com pendentes: #{Amount.full(acc.pending_balance)} BRDC")
    else
      _ ->
        Mix.raise(
          "uso: mix brdc.balance QUEM [--port P] (carteira de teste ou endereço; o nó precisa estar no ar)"
        )
    end
  end
end
