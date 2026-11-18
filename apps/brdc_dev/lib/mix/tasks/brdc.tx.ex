defmodule Mix.Tasks.Brdc.Tx do
  @shortdoc "Mostra uma transação pelo id (ou lista as pendentes e o histórico de uma conta)"
  @moduledoc """
  Mostra uma transação pelo id (64 caracteres hexadecimais): tipo, remetente, taxa, bloco e posição.

      mix brdc.tx ID [--port P] [--dir net]
      mix brdc.tx --pending [--port P] [--dir net]        # o que está esperando bloco
      mix brdc.tx --of NOME_OU_ENDEREÇO [--port P] ...    # histórico de uma conta
  """
  use Mix.Task
  alias BrdcCrypto.Address
  alias BrdcDev.{Cli, Wallets}
  alias BrdcLedger.Amount
  alias BrdcNode.{Client, Explorer}

  @impl Mix.Task
  def run(args) do
    {opts, rest, endpoint, dir} =
      Cli.parse(args, [pending: :boolean, of: :string], @moduledoc, "")

    Cli.ensure_node!(endpoint)

    cond do
      opts[:pending] -> pending(endpoint)
      opts[:of] -> history(endpoint, dir, opts[:of])
      match?([_], rest) -> show(endpoint, hd(rest))
      true -> Mix.raise("use `mix brdc.tx ID`, `--pending` ou `--of CONTA`")
    end
  end

  defp show(endpoint, text) do
    id =
      case Base.decode16(text, case: :mixed) do
        {:ok, <<_::256>> = id} -> id
        _ -> Mix.raise("o id tem 64 caracteres hexadecimais")
      end

    case Client.tx(endpoint, id) do
      {:ok, r} ->
        tx = r.tx

        Mix.shell().info("""
        transação #{Explorer.hex(r.id, full: true)}
          tipo        #{Explorer.kind_label(tx.kind)} (#{tx.kind})
          de          #{Address.from_public_key(tx.sender_pub)}
          nonce       #{tx.nonce}
          taxa        #{Amount.full(tx.fee)} BRDC
          bloco       #{r.height} (posição #{r.index}) · #{Explorer.time(r.time)}
          hash bloco  #{Explorer.hex(r.block_hash, full: true)}
        """)

      {:error, "not_found"} ->
        Mix.raise("transação não encontrada (se acabou de enviar, veja `mix brdc.tx --pending`)")

      {:error, reason} ->
        Mix.raise("não consegui ler: #{inspect(reason)}")
    end
  end

  defp pending(endpoint) do
    case Client.mempool(endpoint) do
      {:ok, []} ->
        Mix.shell().info("nada esperando bloco")

      {:ok, list} ->
        for %{id: id, tx: tx} <- list do
          Mix.shell().info(
            "#{Explorer.hex(id, full: true)}  #{Explorer.kind_label(tx.kind)}  taxa #{Amount.full(tx.fee)}"
          )
        end

      {:error, reason} ->
        Mix.raise("não consegui ler: #{inspect(reason)}")
    end
  end

  defp history(endpoint, dir, who) do
    hash = dir |> Cli.resolve!(who) |> Wallets.hash()

    case Client.account_history(endpoint, hash) do
      {:ok, []} ->
        Mix.shell().info("nenhuma transação (ainda) para #{who}")

      {:ok, rows} ->
        Enum.each(rows, &print_history_row/1)

      {:error, reason} ->
        Mix.raise("não consegui ler: #{inspect(reason)}")
    end
  end

  defp print_history_row(r) do
    role = if r.role == :sender, do: "enviou  ", else: "recebeu "

    Mix.shell().info(
      "bloco #{String.pad_trailing(to_string(r.height), 6)} #{role} #{Explorer.hex(r.id, full: true)}  #{Explorer.kind_label(r.kind)}"
    )
  end
end
