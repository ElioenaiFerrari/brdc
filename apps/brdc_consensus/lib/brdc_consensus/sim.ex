defmodule BrdcConsensus.Sim do
  @moduledoc """
  Simulador determinístico de uma altura de consenso (Fase 3). Tempo **virtual** e acaso com
  **semente**: a mesma configuração dá sempre o mesmo resultado, então um teste que falha pode
  ser repetido. Não abre rede nem usa relógio.

  Comportamentos por nó: `:honest`, `:silent` (nunca fala nem escuta) e `:equivocate` (manda a
  metade dos nós um voto e à outra metade um voto conflitante).

  Rede: atraso aleatório (`delay: {min, max}` em ms), `partition: {[[nós], [nós]], até_ms}`
  (mensagens entre grupos **esperam** o fim da partição: modelo de sincronia parcial) e `drop`
  (probabilidade de perder uma mensagem; usado só em testes de **segurança**, porque o motor
  não retransmite: quem retransmite é a camada de gossip do nó).
  """
  alias BrdcConsensus.{Engine, Vote}

  defstruct nodes: %{},
            queue: :gb_sets.empty(),
            seq: 0,
            time: 0,
            rng: nil,
            opts: %{},
            decisions: %{},
            evidence: [],
            hash_fn: nil

  @doc """
  Roda uma altura. Opções: `:n` (validadores), `:seed` (acaso), `:behaviors` (mapa índice → comportamento),
  `:delay`, `:partition`, `:drop`, `:max_time`, `:valid_fn`, `:height`.
  Devolve `%{decisions: %{índice => {bloco, certificado}}, evidence: [...], time: ms, validators: [...]}`.
  """
  @spec run(keyword()) :: map()
  def run(opts) do
    n = Keyword.fetch!(opts, :n)
    seeds = for i <- 0..(n - 1), do: :crypto.hash(:sha256, "sim-validator-#{i}")
    pubs = Enum.map(seeds, &BrdcCrypto.Ed25519.public_key/1)

    hash_fn = fn block ->
      BrdcCrypto.Hash.tagged("brdc/sim/block", inspect(block))
    end

    behaviors = Keyword.get(opts, :behaviors, %{})

    nodes =
      for {seed, i} <- Enum.with_index(seeds), into: %{} do
        engine =
          Engine.new(
            chain_id: "sim",
            height: Keyword.get(opts, :height, 1),
            validators: pubs,
            seed: seed,
            hash_fn: hash_fn,
            valid_fn: Keyword.get(opts, :valid_fn, fn _ -> true end)
          )

        {i, %{engine: engine, behavior: Map.get(behaviors, i, :honest)}}
      end

    sim = %__MODULE__{
      nodes: nodes,
      rng: :rand.seed_s(:exsss, {Keyword.get(opts, :seed, 1), 2, 3}),
      hash_fn: hash_fn,
      opts: %{
        n: n,
        delay: Keyword.get(opts, :delay, {5, 50}),
        partition: Keyword.get(opts, :partition),
        drop: Keyword.get(opts, :drop, 0.0),
        max_time: Keyword.get(opts, :max_time, 120_000)
      }
    }

    sim = Enum.reduce(0..(n - 1), sim, fn i, acc -> start_node(acc, i) end)
    sim = loop(sim)
    %{decisions: sim.decisions, evidence: sim.evidence, time: sim.time, validators: pubs}
  end

  # --- laço principal -----------------------------------------------------------

  defp loop(sim) do
    honest = for {i, %{behavior: :honest}} <- sim.nodes, do: i

    cond do
      Enum.all?(honest, &Map.has_key?(sim.decisions, &1)) -> sim
      :gb_sets.is_empty(sim.queue) -> sim
      true -> pop_and_run(sim)
    end
  end

  defp pop_and_run(sim) do
    {{time, _seq, ev}, queue} = :gb_sets.take_smallest(sim.queue)

    if time > sim.opts.max_time do
      %{sim | queue: :gb_sets.empty()}
    else
      sim = %{sim | queue: queue, time: time}
      sim |> run_event(ev) |> loop()
    end
  end

  defp run_event(sim, {:deliver, to, msg}), do: feed(sim, to, kind(msg))
  defp run_event(sim, {:timer, node, ev}), do: feed(sim, node, ev)

  defp kind(%Vote{} = v), do: {:vote, v}
  defp kind(%BrdcConsensus.Proposal{} = p), do: {:proposal, p}

  defp start_node(sim, i) do
    case sim.nodes[i].behavior do
      :silent ->
        sim

      _ ->
        {engine, actions} = Engine.start(sim.nodes[i].engine)
        sim |> put_engine(i, engine) |> do_actions(i, actions)
    end
  end

  defp feed(sim, i, ev) do
    case sim.nodes[i] do
      %{behavior: :silent} ->
        sim

      %{engine: engine} ->
        {engine, actions} = Engine.handle(engine, ev)
        sim |> put_engine(i, engine) |> do_actions(i, actions)
    end
  end

  defp put_engine(sim, i, engine),
    do: %{sim | nodes: Map.update!(sim.nodes, i, &%{&1 | engine: engine})}

  # --- ações ------------------------------------------------------------------------

  defp do_actions(sim, i, actions), do: Enum.reduce(actions, sim, &do_action(&2, i, &1))

  defp do_action(sim, i, {:broadcast, msg}) do
    others = for j <- 0..(sim.opts.n - 1), j != i, do: j
    half = div(length(others), 2)
    behavior = sim.nodes[i].behavior

    others
    |> Enum.with_index()
    |> Enum.reduce(sim, fn {j, k}, acc ->
      send_msg(
        acc,
        i,
        j,
        if(behavior == :equivocate and k >= half, do: conflict(sim, i, msg), else: msg)
      )
    end)
  end

  defp do_action(sim, i, {:schedule_timeout, step, r}) do
    base = %{propose: 3_000, prevote: 1_000, precommit: 1_000}[step]
    schedule(sim, sim.time + base + 500 * r, {:timer, i, {:timeout, step, r}})
  end

  defp do_action(sim, i, {:need_block, r}) do
    feed(sim, i, {:block, {:txs, i, r}})
  end

  defp do_action(sim, i, {:decide, block, cert}),
    do: %{sim | decisions: Map.put(sim.decisions, i, {block, cert})}

  defp do_action(sim, _i, {:evidence, ev}), do: %{sim | evidence: [ev | sim.evidence]}

  # voto conflitante do equivocador (mesmo tipo, altura e rodada, outro bloco)
  defp conflict(sim, i, %Vote{} = v) do
    seed = sim.nodes[i].engine.seed
    other = sim.hash_fn.({:evil, v.round})
    Vote.sign("sim", v.type, v.height, v.round, other, seed)
  end

  defp conflict(_sim, _i, msg), do: msg

  # --- rede ---------------------------------------------------------------------------

  defp send_msg(sim, from, to, msg) do
    {r1, rng} = :rand.uniform_s(sim.rng)
    {min, max} = sim.opts.delay
    {r2, rng} = :rand.uniform_s(max - min + 1, rng)
    sim = %{sim | rng: rng}

    if r1 < sim.opts.drop do
      sim
    else
      schedule(sim, arrival(sim, from, to, sim.time + min + r2 - 1), {:deliver, to, msg})
    end
  end

  # mensagens entre grupos separados esperam o fim da partição
  defp arrival(%{opts: %{partition: {groups, heal}}}, from, to, t) when t < heal do
    if Enum.find(groups, &(from in &1)) == Enum.find(groups, &(to in &1)),
      do: t,
      else: heal + ((t - heal) |> abs() |> rem(50))
  end

  defp arrival(_sim, _from, _to, t), do: t

  defp schedule(sim, time, ev) do
    %{sim | queue: :gb_sets.add({time, sim.seq, ev}, sim.queue), seq: sim.seq + 1}
  end
end
