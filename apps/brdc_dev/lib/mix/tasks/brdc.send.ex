defmodule Mix.Tasks.Brdc.Send do
  @shortdoc "Uma carteira de TESTE envia BRDC a outra (ou a um endereço)"
  @moduledoc """
  A carteira de teste `DE` assina uma transferência (com a taxa mínima) para `PARA` e espera o bloco. Só
  desenvolvimento (a chave da carteira de teste fica no arquivo).

      mix brdc.send DE PARA VALOR [--no-wait] [--port P] [--dir net]

  `DE`: nome de carteira de teste. `PARA`: nome de carteira de teste ou endereço `brdc1…`. `VALOR` em BRDC.
  """
  use Mix.Task
  alias BrdcDev.{Chain, Cli, Wallets}
  alias BrdcLedger.{Amount, Tx}

  @impl Mix.Task
  def run(args) do
    {opts, rest, endpoint, net_dir} = Cli.parse(args, [no_wait: :boolean], @moduledoc, "")

    [from, to, value] =
      if match?([_, _, _], rest), do: rest, else: Mix.raise("uso: mix brdc.send DE PARA VALOR")

    units = Cli.amount!(value)

    sender =
      case Cli.resolve!(net_dir, from) do
        {:wallet, w} ->
          w

        {:address, _} ->
          Mix.raise("DE precisa ser uma carteira de teste (com a chave), não um endereço")
      end

    dest = to |> then(&Cli.resolve!(net_dir, &1)) |> Wallets.hash()
    Cli.ensure_node!(endpoint)
    me = Wallets.hash({:wallet, sender})

    case Chain.send_tx(
           endpoint,
           sender.account.seed,
           Tx.transfer_kind(),
           Tx.transfer_payload(dest, units),
           :min
         ) do
      {:ok, sent} ->
        Mix.shell().info("transferência de #{Amount.full(units)} BRDC enviada")

        if !opts[:no_wait] do
          :ok = Chain.await_included(endpoint, me, sent.nonce)
          {:ok, a} = Chain.balance(endpoint, me)
          {:ok, b} = Chain.balance(endpoint, dest)

          Mix.shell().info(
            "incluída; #{from} #{Amount.full(a)} BRDC · #{to} #{Amount.full(b)} BRDC"
          )
        end

      {:error, reason} ->
        Mix.raise("a rede recusou: #{inspect(reason)}")
    end
  end
end
