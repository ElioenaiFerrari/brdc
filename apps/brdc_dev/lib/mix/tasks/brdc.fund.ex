defmodule Mix.Tasks.Brdc.Fund do
  @shortdoc "SIMULA os emissores criando BRDC de teste para um endereço (só dev)"
  @moduledoc """
  Cria BRDC de TESTE para um endereço, assinando como os dois emissores da rede de teste local.

      mix brdc.fund brdc1… 1000        # 1000 BRDC (aceita decimais: 12,5)
      mix brdc.fund brdc1… 50 --port 4545 --dir net

  **Só desenvolvimento:** usa as chaves dos emissores de `net/`. Fala com o nó pela porta pública, então o
  nó precisa estar rodando (`iex -S mix phx.server` ou `mix brdc.devnet`).
  """
  use Mix.Task
  alias BrdcCrypto.Address
  alias BrdcDev.{Devnet, Funding}
  alias BrdcLedger.Amount

  @impl Mix.Task
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [port: :integer, dir: :string])
    Mix.Task.run("app.config")

    case rest do
      [address, amount] -> fund(address, amount, opts)
      _ -> Mix.raise("uso: mix brdc.fund ENDEREÇO VALOR [--port 4545] [--dir net]")
    end
  end

  defp fund(address, amount, opts) do
    with {:ok, addr_hash} <- Address.decode(address),
         {:ok, units} <- Amount.parse(amount),
         {:ok, devnet} <- Devnet.ensure(opts[:dir] || Devnet.default_dir()),
         endpoint = {~c"127.0.0.1", opts[:port] || 4545},
         {:ok, id} <- Funding.mint(endpoint, devnet, addr_hash, units) do
      Mix.shell().info("enviado ao nó: #{Base.encode16(id, case: :lower)}")
      Mix.shell().info("o saldo aparece depois do próximo bloco (cerca de 1 s)")
    else
      {:error, :bad_checksum} -> Mix.raise("endereço inválido (checksum)")
      {:error, reason} -> Mix.raise("não consegui: #{inspect(reason)}")
      :error -> Mix.raise("valor inválido: use números, vírgula decimal e no máximo 6 casas")
    end
  end
end
