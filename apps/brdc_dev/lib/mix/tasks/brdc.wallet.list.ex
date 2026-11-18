defmodule Mix.Tasks.Brdc.Wallet.List do
  @shortdoc "Lista as carteiras de TESTE (e o saldo, se o nó estiver no ar)"
  @moduledoc """
  Lista as carteiras de teste de `net/wallets/` com endereço e, se um nó responder, o saldo.

      mix brdc.wallet.list [--port P] [--dir net]
  """
  use Mix.Task
  alias BrdcDev.{Chain, Cli, Wallets}
  alias BrdcLedger.Amount
  alias BrdcNode.Client

  @impl Mix.Task
  def run(args) do
    {_opts, _rest, endpoint, net_dir} = Cli.parse(args, [], @moduledoc, "")
    online = match?({:ok, _}, Client.status(endpoint))
    names = Wallets.names(net_dir)

    if names == [],
      do: Mix.shell().info("nenhuma carteira de teste; crie com `mix brdc.wallet.new NOME`")

    for name <- names, {:ok, w} <- [Wallets.load(net_dir, name)] do
      Mix.shell().info(
        "  #{String.pad_trailing(name, 16)} #{w.account.address}  #{balance_text(online, endpoint, w)}"
      )
    end
  end

  defp balance_text(false, _endpoint, _wallet), do: "(nó fora do ar)"

  defp balance_text(true, endpoint, wallet) do
    case Chain.balance(endpoint, Wallets.hash({:wallet, wallet})) do
      {:ok, units} -> "#{Amount.full(units)} BRDC"
      _ -> "?"
    end
  end
end
