defmodule Mix.Tasks.Brdc.Wallet.New do
  @shortdoc "Cria uma carteira de TESTE nomeada"
  @moduledoc """
  Cria uma carteira de teste (frase de 12 palavras) em `net/wallets/NOME.json`, para simular pessoas sem abrir o
  navegador. **Só desenvolvimento:** a frase fica em texto puro no arquivo.

      mix brdc.wallet.new NOME [--dir net]

  NOME: minúsculas, dígitos, `-` e `_`, até 32 caracteres. Use o nome onde as outras tarefas pedem uma carteira
  (`mix brdc.mint alice 100`, `mix brdc.send alice bob 10`).
  """
  use Mix.Task
  alias BrdcDev.{Cli, Wallets}

  @impl Mix.Task
  def run(args) do
    {_opts, rest, _endpoint, net_dir} = Cli.parse(args, [], @moduledoc, "")

    case rest do
      [name] ->
        case Wallets.create(net_dir, name) do
          {:ok, w} ->
            Mix.shell().info("carteira de teste #{name}: #{w.account.address}")

          {:error, :exists} ->
            Mix.raise("já existe uma carteira de teste chamada #{name}")

          {:error, :bad_name} ->
            Mix.raise("nome inválido: minúsculas, dígitos, - e _, até 32 caracteres")
        end

      _ ->
        Mix.raise("uso: mix brdc.wallet.new NOME")
    end
  end
end
