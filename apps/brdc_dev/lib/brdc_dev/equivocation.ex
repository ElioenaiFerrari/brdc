defmodule BrdcDev.Equivocation do
  @moduledoc """
  SIMULA um validador que **equivoca**: assina e envia **dois votos conflitantes** (mesmo tipo, altura e rodada,
  blocos diferentes), o pior comportamento de um validador no BFT. Usa a semente de um validador de TESTE (o
  verdadeiro precisa estar parado), entra na rede pelos pares com a identidade dele e depois confere, pela
  consulta de consenso da porta pública, se os validadores **honestos detectaram** (`evidence` subiu).

  O motor do honesto abre a altura seguinte quando recebe um voto dela, então não é preciso tráfego para
  provocar a detecção. **Só detecção**: não há stake nem punição (docs/flows/23-equivocation.md). Só desenvolvimento,
  nunca em release de produção.
  """
  alias BrdcConsensus.Vote
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcDev.{Funding, Net}
  alias BrdcNode.{Client, Genesis, Keygen, Peers}
  alias BrdcP2p.Guard

  @type report :: %{
          equivocator: String.t(),
          pairs_sent: non_neg_integer(),
          height: pos_integer() | nil,
          evidence: [%{endpoint: tuple(), before: non_neg_integer(), after: non_neg_integer()}],
          detected: non_neg_integer(),
          honest: non_neg_integer(),
          passed: boolean()
        }

  @doc """
  Opções: `genesis:` e `seed:` (caminhos), `endpoints:` (portas públicas dos validadores **honestos**, para ler as
  evidências), `peer_port:` (onde escutar; é a porta que os outros usam para achar este validador), `peers:`
  (padrão: o `bootstrap` da gênese), `duration_ms:` (padrão 10 000) e `connect_ms:` (padrão 30 000).
  """
  @spec run(keyword()) :: {:ok, report()} | {:error, term()}
  def run(opts) do
    with {:ok, text} <- File.read(Keyword.fetch!(opts, :genesis)),
         {:ok, genesis} <- Genesis.from_json(text),
         {:ok, seed} <- Keygen.load_seed(Keyword.fetch!(opts, :seed)),
         pub = Ed25519.public_key(seed),
         :ok <- member(genesis, pub) do
      attack(genesis, seed, pub, opts)
    end
  end

  defp member(genesis, pub),
    do: if(pub in genesis.validators, do: :ok, else: {:error, :not_a_validator})

  defp attack(genesis, seed, pub, opts) do
    endpoints = Keyword.fetch!(opts, :endpoints)

    peers =
      Keyword.get_lazy(opts, :peers, fn ->
        for b <- genesis.bootstrap,
            b.validator != pub,
            do: %{pub: b.validator, host: b.host, port: b.port}
      end)

    {:ok, guard} = Guard.start_link(sweep_ms: 60_000)

    {:ok, net} =
      Peers.start_link(
        genesis: genesis,
        seed: seed,
        owner: self(),
        guard: guard,
        port: Keyword.get(opts, :peer_port, 0),
        peers: peers
      )

    try do
      with true <-
             wait_connected(net, length(peers), Keyword.get(opts, :connect_ms, 30_000)) ||
               {:error, :no_peers},
           :ok <- readable(endpoints) do
        before = evidence(endpoints)
        deadline = now() + Keyword.get(opts, :duration_ms, 10_000)
        {pairs, height} = inject(net, genesis.chain_id, seed, endpoints, before, deadline, 0, nil)
        {:ok, report(pub, endpoints, before, pairs, height)}
      end
    after
      GenServer.stop(net)
      GenServer.stop(guard)
    end
  end

  @doc """
  Depois da equivocação, a rede ainda produz bloco? Envia uma emissão de teste a `entry` (um ponto de entrada) e
  espera até 45 s que **todos** os `endpoints` honestos passem da altura em que estavam (com 3 de 4 o quórum de
  mais de 2/3 se mantém). `devnet` é o que `BrdcDev.Devnet.ensure/2` devolve (as sementes dos emissores de teste).
  """
  @spec alive_after?(tuple(), map(), [tuple()]) :: boolean()
  def alive_after?(entry, devnet, endpoints) do
    before = for ep <- endpoints, {:ok, st} <- [Client.status(ep)], do: st.height
    target = Enum.max(before, fn -> 0 end) + 1
    to = Address.hash(:crypto.strong_rand_bytes(32))

    case Funding.mint(entry, devnet, to, 1_000_000) do
      {:ok, _} -> Net.wait_until(fn -> all_reached?(endpoints, target) end, 45_000)
      _ -> false
    end
  end

  defp all_reached?(endpoints, target),
    do:
      Enum.all?(endpoints, fn ep ->
        match?({:ok, %{height: h}} when h >= target, Client.status(ep))
      end)

  @doc "O veredito em linhas de texto (o mesmo para a tarefa `mix` e para o container)."
  @spec describe(report()) :: [String.t()]
  def describe(r) do
    rows =
      for e <- r.evidence do
        {host, port} = e.endpoint

        "  #{host}:#{port}  evidências #{e.before} -> #{e.after}#{if e.after > e.before, do: "  (detectou)", else: "  (NÃO detectou)"}"
      end

    [
      "validador bizantino #{r.equivocator}: #{r.pairs_sent} par(es) de votos conflitantes para a altura #{r.height}",
      "detectaram #{r.detected} de #{r.honest} validadores honestos:"
    ] ++ rows
  end

  # tenta até detectarem (ou acabar o tempo): um par de votos por tentativa, de blocos inventados
  defp inject(net, chain, seed, endpoints, before, deadline, pairs, _height) do
    height = next_height(endpoints)
    a = :crypto.strong_rand_bytes(32)
    b = :crypto.strong_rand_bytes(32)
    Peers.broadcast(net, {:vote, Vote.sign(chain, :prevote, height, 0, a, seed)})
    Peers.broadcast(net, {:vote, Vote.sign(chain, :prevote, height, 0, b, seed)})
    flush()

    cond do
      await_evidence(endpoints, before, 1_500) -> {pairs + 1, height}
      now() > deadline -> {pairs + 1, height}
      true -> inject(net, chain, seed, endpoints, before, deadline, pairs + 1, height)
    end
  end

  defp await_evidence(endpoints, before, ms) do
    deadline = now() + ms
    do_await(endpoints, before, deadline)
  end

  defp do_await(endpoints, before, deadline) do
    cond do
      detected?(endpoints, before) -> true
      now() > deadline -> false
      true -> Process.sleep(100) && do_await(endpoints, before, deadline)
    end
  end

  defp detected?(endpoints, before) do
    now_ev = evidence(endpoints)
    Enum.all?(endpoints, fn ep -> Map.get(now_ev, ep, 0) > Map.get(before, ep, 0) end)
  end

  defp report(pub, endpoints, before, pairs, height) do
    after_ev = evidence(endpoints)

    rows =
      for ep <- endpoints,
          do: %{endpoint: ep, before: Map.get(before, ep, 0), after: Map.get(after_ev, ep, 0)}

    detected = Enum.count(rows, &(&1.after > &1.before))

    %{
      equivocator: Address.from_public_key(pub),
      pairs_sent: pairs,
      height: height,
      evidence: rows,
      detected: detected,
      honest: length(endpoints),
      passed: detected == length(endpoints)
    }
  end

  # a próxima altura = a maior altura que os honestos informam + 1
  defp next_height(endpoints) do
    heights = for ep <- endpoints, {:ok, st} <- [Client.status(ep)], do: st.height
    Enum.max(heights, fn -> 0 end) + 1
  end

  # Antes de atacar, confere que dá para LER a evidência de cada honesto: sem isso, "não consegui ler" viraria
  # "zero evidências" e o veredito seria um falso negativo (um nó sem a consulta de consenso responde erro).
  defp readable(endpoints) do
    bad = for ep <- endpoints, not match?({:ok, _}, Client.consensus_info(ep)), do: ep
    if bad == [], do: :ok, else: {:error, {:consensus_unavailable, bad}}
  end

  # evidências de cada validador honesto, segundo ele mesmo
  defp evidence(endpoints) do
    for ep <- endpoints, into: %{} do
      case Client.consensus_info(ep) do
        {:ok, %{evidence: n}} -> {ep, n}
        _ -> {ep, 0}
      end
    end
  end

  defp wait_connected(_net, 0, _ms), do: true

  defp wait_connected(net, want, ms) do
    deadline = now() + ms
    do_wait(net, want, deadline)
  end

  defp do_wait(net, want, deadline) do
    cond do
      length(Peers.connected(net)) >= want -> true
      now() > deadline -> false
      true -> Process.sleep(100) && do_wait(net, want, deadline)
    end
  end

  # o dono recebe tudo o que os pares mandam; aqui nada disso interessa
  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
