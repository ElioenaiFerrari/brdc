defmodule BrdcDev.Cli do
  @moduledoc """
  Preâmbulo comum das tarefas de cliente (`brdc.mint`, `brdc.send`…): opções `--port` e `--dir`, quem é o
  destino (nome de carteira de teste ou endereço) e leitura de valores. Só desenvolvimento.
  """
  alias BrdcDev.{Net, Wallets}
  alias BrdcLedger.Amount

  @common [port: :integer, dir: :string]

  @doc "Opções comuns que toda tarefa de cliente aceita."
  @spec common() :: keyword()
  def common, do: @common

  @doc "Lê os argumentos (com as opções comuns mais `extra`), prepara o app e devolve `{opts, rest, endpoint, net_dir}`."
  @spec parse([String.t()], keyword(), String.t(), String.t()) ::
          {keyword(), [String.t()], tuple(), Path.t()}
  def parse(args, extra, doc, usage) do
    if Net.help?(args, doc), do: exit(:normal)
    {opts, rest, _} = OptionParser.parse(args, strict: @common ++ extra)
    Mix.Task.run("app.config")
    _ = usage
    {opts, rest, Net.client_endpoint(opts), Net.dir(opts)}
  end

  @doc "Quem é `who`: carteira de teste (com chave) ou endereço. Erro claro se não achar."
  @spec resolve!(Path.t(), String.t()) :: {:wallet, map()} | {:address, <<_::256>>}
  def resolve!(net_dir, who) do
    case Wallets.resolve(net_dir, who) do
      {:error, :not_found} ->
        Mix.raise(
          "não há carteira de teste chamada #{who} (crie com `mix brdc.wallet.new #{who}`) nem endereço brdc1…"
        )

      {:error, {:bad_address, reason}} ->
        Mix.raise("endereço inválido (#{reason})")

      {:error, reason} ->
        Mix.raise("não consegui ler #{who}: #{inspect(reason)}")

      ok ->
        ok
    end
  end

  @doc "Lê um valor em BRDC (`12,5`, `1.000`)."
  @spec amount!(String.t()) :: pos_integer()
  def amount!(text) do
    case Amount.parse(text) do
      {:ok, units} when units > 0 ->
        units

      _ ->
        Mix.raise(
          "valor inválido: #{inspect(text)} (use números, vírgula decimal, até 6 casas; ponto só como milhar: 1.000,50)"
        )
    end
  end

  @doc "O nó responde? Se não, explica como subir."
  @spec ensure_node!(tuple()) :: map()
  def ensure_node!(endpoint) do
    case BrdcNode.Client.status(endpoint) do
      {:ok, status} ->
        status

      {:error, _} ->
        Mix.raise(
          "nenhum nó respondeu em #{elem(endpoint, 1)}: suba a rede com `mix brdc.devnet.up` (ou `mix phx.server`) ou informe `--port`"
        )
    end
  end
end
