defmodule Mix.Tasks.Brdc.Balance do
  @shortdoc "Mostra o saldo de um endereço no nó local"
  @moduledoc """
  Consulta o nó pela porta pública (não confia nele: por ora só lê).

      mix brdc.balance brdc1… [--port 4545]
  """
  use Mix.Task
  alias BrdcCrypto.Address
  alias BrdcLedger.Amount
  alias BrdcNode.Client

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [port: :integer])
    Mix.Task.run("app.config")
    endpoint = {~c"127.0.0.1", opts[:port] || 4545}

    with [address] <- rest,
         {:ok, hash} <- Address.decode(address),
         {:ok, status} <- Client.status(endpoint),
         {:ok, acc} <- Client.account(endpoint, hash) do
      Mix.shell().info(
        "rede: #{status.chain_id} · altura #{status.height} · pendentes #{status.pending}"
      )

      Mix.shell().info("saldo: #{Amount.full(acc.balance)} BRDC (nonce #{acc.nonce})")

      if acc.pending_balance != acc.balance,
        do: Mix.shell().info("com pendentes: #{Amount.full(acc.pending_balance)} BRDC")
    else
      _ -> Mix.raise("uso: mix brdc.balance ENDEREÇO [--port 4545] (o nó precisa estar rodando)")
    end
  end
end
