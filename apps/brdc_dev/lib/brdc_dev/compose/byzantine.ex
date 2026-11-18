defmodule BrdcDev.Compose.Byzantine do
  @moduledoc """
  Papel `equivocator` de um container do laboratório Docker: roda **uma vez** o simulador de equivocação
  (`BrdcDev.Equivocation`) com a semente de um validador de teste, imprime o veredito e encerra o container com
  código 0 (todos os honestos detectaram) ou 1. Os honestos e a porta de cada um vêm da gênese (nomes de serviço).
  Só desenvolvimento.
  """
  use GenServer
  alias BrdcCrypto.Ed25519
  alias BrdcDev.Equivocation
  alias BrdcNode.{Genesis, Keygen}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts), do: {:ok, opts, {:continue, :run}}

  @impl true
  def handle_continue(:run, opts) do
    code = run(opts)
    # `System.stop/1` encerra a VM com esse código de saída (o `docker compose run` o repassa)
    System.stop(code)
    {:noreply, opts}
  end

  defp run(opts) do
    with {:ok, text} <- File.read(opts[:genesis]),
         {:ok, genesis} <- Genesis.from_json(text),
         {:ok, seed} <- Keygen.load_seed(opts[:seed]) do
      attack(opts, genesis, Ed25519.public_key(seed))
    else
      other ->
        IO.puts("VEREDITO: não consegui ler a gênese ou a semente: #{inspect(other)}")
        1
    end
  end

  defp attack(opts, genesis, me) do
    endpoints =
      for b <- genesis.bootstrap,
          b.validator != me,
          do: {String.to_charlist(b.host), opts[:public_port]}

    result =
      Equivocation.run(
        genesis: opts[:genesis],
        seed: opts[:seed],
        endpoints: endpoints,
        peer_port: opts[:peer_port],
        duration_ms: 30_000
      )

    print(result)
  end

  defp print({:ok, report}) do
    for line <- Equivocation.describe(report), do: IO.puts(line)

    IO.puts(
      if report.passed, do: "VEREDITO: DETECTADA por todos os honestos", else: "VEREDITO: FALHOU"
    )

    if report.passed, do: 0, else: 1
  end

  defp print({:error, reason}) do
    IO.puts("VEREDITO: não consegui simular: #{inspect(reason)}")
    1
  end
end
