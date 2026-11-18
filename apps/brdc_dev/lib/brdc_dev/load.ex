defmodule BrdcDev.Load do
  @moduledoc """
  Teste de carga do laboratório Docker (`mix brdc.compose.load`, docs/flows/24-load-test.md).

  **Carga aberta, em degraus de taxa**: cada degrau oferece uma taxa fixa de transferências por segundo, repartida
  entre N remetentes (cada um fala com UM validador, para a ordem dos nonces valer), e mede o que acontece. Ao
  contrário de um laço fechado (mandar o mais rápido possível), isso mostra **onde** a rede satura.

  Medidas de cada degrau:
  - **taxa oferecida × aceita** pelos nós (e os motivos das recusas) e a latência de ida e volta do envio;
  - **latência de confirmação** de cada transação (do envio até o nonce confirmado do remetente passar dela, lido
    a cada 100 ms: precisão de ~100 ms), com p50, p95, p99 e máximo;
  - **esvaziamento**: quanto leva para o que ficou pendente virar bloco e quantas transações **não** confirmaram;
  - **blocos**: quantos, transações por bloco e intervalo médio;
  - **CPU e memória lidas do cgroup** de cada validador (CPU usada em núcleos, **tempo em throttle** e fração de
    períodos limitados, memória atual e pico, `oom_kill`);
  - **saúde**: reinícios e OOM de cada container, mesma altura e mesmo bloco nos validadores, evidências.

  Só desenvolvimento.
  """
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcDev.Funding
  alias BrdcLedger.{Executor, Params, Tx}
  alias BrdcNode.Client

  # --- partes puras (testadas sem Docker) ---------------------------------------------------------

  @doc "Percentil `p` (0..1) de uma lista já ordenada (método do posto mais próximo); `nil` se vazia."
  @spec percentile([number()], float()) :: number() | nil
  def percentile([], _p), do: nil

  def percentile(sorted, p) when p >= 0 and p <= 1 do
    n = length(sorted)
    Enum.at(sorted, max(0, min(n - 1, ceil(p * n) - 1)))
  end

  @doc "Resumo de latências em microssegundos, devolvido em milissegundos: `%{n, p50, p95, p99, max}`."
  @spec summarize([non_neg_integer()]) :: map()
  def summarize(micros) do
    sorted = Enum.sort(micros)
    ms = fn v -> if v, do: Float.round(v / 1000, 1), else: nil end

    %{
      n: length(sorted),
      p50: ms.(percentile(sorted, 0.50)),
      p95: ms.(percentile(sorted, 0.95)),
      p99: ms.(percentile(sorted, 0.99)),
      max: ms.(List.last(sorted))
    }
  end

  @doc """
  Lê a saída do comando de cgroup (`cpu.stat` mais as linhas `MEM`, `MAX`, `PEAK` e `oom_kill`) num mapa de inteiros.
  Chave ausente simplesmente não aparece (o pico de memória não existe em kernels antigos).
  """
  @spec parse_cgroup(String.t()) :: %{atom() => integer()}
  def parse_cgroup(text) do
    keys = %{
      "usage_usec" => :usage_usec,
      "nr_periods" => :nr_periods,
      "nr_throttled" => :nr_throttled,
      "throttled_usec" => :throttled_usec,
      "MEM" => :mem,
      "MAX" => :mem_max,
      "PEAK" => :mem_peak,
      "oom_kill" => :oom_kill
    }

    for line <- String.split(text, "\n", trim: true),
        [k, v] <- [String.split(line)],
        key = keys[k],
        {n, ""} <- [Integer.parse(v)],
        into: %{},
        do: {key, n}
  end

  @doc """
  Diferença entre duas leituras do cgroup, em `secs` segundos: núcleos de CPU usados, tempo e fração de períodos
  em throttle, memória atual e pico, e mortes por falta de memória.
  """
  @spec cgroup_delta(map(), map(), number()) :: map()
  def cgroup_delta(a, b, secs) do
    periods = Map.get(b, :nr_periods, 0) - Map.get(a, :nr_periods, 0)
    throttled = Map.get(b, :nr_throttled, 0) - Map.get(a, :nr_throttled, 0)

    %{
      cpu_cores:
        Float.round(
          (Map.get(b, :usage_usec, 0) - Map.get(a, :usage_usec, 0)) / 1_000_000 / secs,
          3
        ),
      throttled_s:
        Float.round(
          (Map.get(b, :throttled_usec, 0) - Map.get(a, :throttled_usec, 0)) / 1_000_000,
          2
        ),
      throttled_pct: if(periods > 0, do: Float.round(100 * throttled / periods, 1), else: 0.0),
      mem_mib: Float.round(Map.get(b, :mem, 0) / 1_048_576, 0),
      mem_peak_mib: Float.round(Map.get(b, :mem_peak, Map.get(b, :mem, 0)) / 1_048_576, 0),
      mem_max_mib: Float.round(Map.get(b, :mem_max, 0) / 1_048_576, 0),
      oom_kill: Map.get(b, :oom_kill, 0) - Map.get(a, :oom_kill, 0)
    }
  end

  @doc "Instante (em µs, relativo ao início) do envio de número `k` a `per_sender_rate` envios por segundo."
  @spec send_at_us(non_neg_integer(), number()) :: non_neg_integer()
  def send_at_us(k, per_sender_rate), do: round(k * 1_000_000 / per_sender_rate)

  # --- contexto: contas e rede ------------------------------------------------------------------

  @doc """
  Prepara a carga: cria `n` contas de remetente e as financia (fora de qualquer medição). Devolve o contexto.
  `eps` são as portas públicas dos validadores; `devnet` vem de `BrdcDev.Devnet.ensure/2`.
  """
  @spec prepare([tuple()], map(), pos_integer()) :: map()
  def prepare(eps, devnet, n) do
    {:ok, st} = Client.status(hd(eps))

    accounts =
      for i <- 1..n do
        seed = :crypto.strong_rand_bytes(32)

        %{
          i: i,
          seed: seed,
          pub: Ed25519.public_key(seed),
          ep: Enum.at(eps, rem(i - 1, length(eps)))
        }
      end

    for a <- accounts do
      {:ok, _} = Funding.mint(a.ep, devnet, Address.hash(a.pub), 1_000_000_000)
      wait_until(fn -> confirmed_balance?(a) end, 30_000)
    end

    %{
      eps: eps,
      accounts: accounts,
      chain_id: st.chain_id,
      params: struct(Params, transfer_base: st.transfer_base, per_byte: st.per_byte)
    }
  end

  defp confirmed_balance?(a),
    do: match?({:ok, %{balance: b}} when b > 0, Client.account(a.ep, Address.hash(a.pub)))

  # --- um degrau --------------------------------------------------------------------------------

  @doc """
  Roda UM degrau: oferece `rate` tx/s por `duration_ms`, espera esvaziar (até `drain_ms`) e devolve as medidas.
  `snap` é uma função `() -> %{nome => leitura do cgroup}` e `health` outra, `() -> map` (reinícios etc.); as duas
  são chamadas antes e depois, para as diferenças serem do degrau.
  """
  @spec step(map(), number(), pos_integer(), pos_integer(), (-> map()), (-> map())) :: map()
  def step(ctx, rate, duration_ms, drain_ms, snap, health) do
    n = length(ctx.accounts)
    per_sender = rate / n
    before = %{cg: snap.(), health: health.(), net: net_state(ctx.eps), at: now_ms()}

    base =
      for a <- ctx.accounts, do: elem(Client.account(a.ep, Address.hash(a.pub)), 1).pending_nonce

    t0 = System.monotonic_time(:microsecond)
    deadline_us = t0 + duration_ms * 1_000
    parent = self()

    trackers =
      for a <- ctx.accounts,
          do:
            spawn_link(fn ->
              track(parent, a, [], :queue.new(), nil, now_ms() + duration_ms + drain_ms)
            end)

    senders =
      for {{a, nonce0}, tracker} <- Enum.zip(Enum.zip(ctx.accounts, base), trackers) do
        Task.async(fn -> send_loop(ctx, a, nonce0, per_sender, t0, deadline_us, tracker) end)
      end

    sent = Enum.map(senders, &Task.await(&1, duration_ms + 60_000))
    send_end = now_ms()
    for t <- trackers, do: send(t, :senders_done)
    track_results = for _ <- trackers, do: await_tracked(drain_ms + 30_000)

    after_send = net_state(ctx.eps)
    drain_s = (now_ms() - send_end) / 1_000
    Process.sleep(1_000)
    secs = duration_ms / 1_000
    ending = %{cg: snap.(), health: health.(), net: net_state(ctx.eps), at: now_ms()}

    accepted = sent |> Enum.map(& &1.ok) |> Enum.sum()

    errs =
      Enum.reduce(sent, %{}, fn s, acc -> Map.merge(acc, s.errs, fn _, x, y -> x + y end) end)

    unconfirmed = track_results |> Enum.map(& &1.unconfirmed) |> Enum.sum()

    %{
      rate: rate,
      duration_s: Float.round(secs, 1),
      offered: offered(per_sender, n, duration_ms),
      accepted: accepted,
      accepted_rate: Float.round(accepted / secs, 1),
      errors: errs,
      rtt: summarize(Enum.flat_map(sent, & &1.rtts)),
      confirm: summarize(Enum.flat_map(track_results, & &1.lats)),
      confirmed: length(Enum.flat_map(track_results, & &1.lats)),
      unconfirmed: unconfirmed,
      backlog_after_send: after_send.pending,
      drain_s: Float.round(drain_s, 1),
      blocks: blocks_between(ctx.eps, before.net.height, ending.net.height),
      cgroup:
        for(
          {name, a} <- before.cg,
          do:
            {name, cgroup_delta(a, Map.fetch!(ending.cg, name), (ending.at - before.at) / 1_000)}
        ),
      health_before: before.health,
      health_after: ending.health,
      gossip: gossip_delta(before.net.gossip, ending.net.gossip),
      net: ending.net
    }
  end

  defp await_tracked(timeout) do
    receive do
      {:tracked, r} -> r
    after
      timeout -> %{lats: [], unconfirmed: -1}
    end
  end

  @doc "Quantos envios o calendário de `n` remetentes a `per_sender` tx/s faz em `duration_ms` (inclui o instante 0)."
  @spec offered(number(), pos_integer(), pos_integer()) :: non_neg_integer()
  def offered(per_sender, n, duration_ms), do: n * ceil(per_sender * duration_ms / 1_000)

  # um remetente: no instante k do calendário envia a transação; se atrasar, envia logo (mede o atraso)
  defp send_loop(ctx, a, nonce0, per_sender, t0, deadline_us, tracker) do
    loop = fn loop, k, nonce, acc ->
      due = t0 + send_at_us(k, per_sender)
      if due >= deadline_us, do: acc, else: send_one(ctx, a, due, nonce, k, acc, tracker, loop)
    end

    loop.(loop, 0, nonce0, %{ok: 0, errs: %{}, rtts: [], late: 0})
  end

  defp send_one(ctx, a, due, nonce, k, acc, tracker, loop) do
    wait = div(due - System.monotonic_time(:microsecond), 1_000)
    if wait > 0, do: Process.sleep(wait)
    late = if System.monotonic_time(:microsecond) - due > 50_000, do: 1, else: 0

    base = %Tx{
      chain_id: ctx.chain_id,
      kind: 1,
      nonce: nonce,
      fee: 0,
      sender_pub: a.pub,
      payload: Tx.transfer_payload(:crypto.strong_rand_bytes(32), 1)
    }

    tx = %{base | fee: Executor.min_fee(ctx.params, base)} |> Tx.sign(a.seed)
    t = System.monotonic_time(:microsecond)
    submitted = now_ms()
    result = Client.submit_tx(a.ep, Tx.encode(tx))
    rtt = System.monotonic_time(:microsecond) - t

    case result do
      {:ok, _} ->
        send(tracker, {:sent, nonce, submitted})

        loop.(loop, k + 1, nonce + 1, %{
          acc
          | ok: acc.ok + 1,
            rtts: [rtt | acc.rtts],
            late: acc.late + late
        })

      {:error, reason} ->
        errs = Map.update(acc.errs, inspect(reason), 1, &(&1 + 1))
        loop.(loop, k + 1, nonce, %{acc | errs: errs, late: acc.late + late})
    end
  end

  # o acompanhante de um remetente: a cada 100 ms lê o nonce confirmado e fecha as transações já confirmadas
  defp track(parent, a, lats, queue, done, give_up) do
    receive do
      {:sent, nonce, t} -> track(parent, a, lats, :queue.in({nonce, t}, queue), done, give_up)
      :senders_done -> track(parent, a, lats, queue, true, give_up)
    after
      100 ->
        {lats, queue} = settle(a, lats, queue)

        cond do
          done && :queue.is_empty(queue) ->
            send(parent, {:tracked, %{lats: lats, unconfirmed: 0}})

          done && now_ms() > give_up ->
            send(parent, {:tracked, %{lats: lats, unconfirmed: :queue.len(queue)}})

          true ->
            track(parent, a, lats, queue, done, give_up)
        end
    end
  end

  defp settle(a, lats, queue) do
    case Client.account(a.ep, Address.hash(a.pub)) do
      {:ok, %{nonce: confirmed}} -> pop_confirmed(queue, confirmed, now_ms(), lats)
      _ -> {lats, queue}
    end
  end

  defp pop_confirmed(queue, confirmed, now, lats) do
    case :queue.peek(queue) do
      {:value, {nonce, t}} when nonce < confirmed ->
        pop_confirmed(:queue.drop(queue), confirmed, now, [(now - t) * 1_000 | lats])

      _ ->
        {lats, queue}
    end
  end

  # --- estado da rede e blocos --------------------------------------------------------------------

  @doc "Alturas, hashes, pendentes e evidências de cada validador: `%{height, same?, pending, evidence}`."
  @spec net_state([tuple()]) :: map()
  def net_state(eps) do
    sts = for ep <- eps, {:ok, s} <- [Client.status(ep)], do: s
    cons = for ep <- eps, {:ok, c} <- [Client.consensus_info(ep)], do: c

    %{
      height: sts |> Enum.map(& &1.height) |> Enum.min(fn -> 0 end),
      heights: Enum.map(sts, & &1.height),
      same?: sts |> Enum.map(&{&1.height, &1.last_hash}) |> Enum.uniq() |> length() == 1,
      pending: sts |> Enum.map(& &1.pending) |> Enum.sum(),
      pendings: Enum.map(sts, & &1.pending),
      evidence: cons |> Enum.map(& &1.evidence) |> Enum.sum(),
      gossip: sum_gossip(cons)
    }
  end

  # soma, nos validadores, o que aconteceu com as transações que chegaram por fofoca
  defp sum_gossip(cons) do
    Enum.reduce(cons, %{ok: 0, duplicate: 0, rejected: %{}}, fn c, acc ->
      g = c.gossip

      %{
        ok: acc.ok + g.ok,
        duplicate: acc.duplicate + g.duplicate,
        rejected: Map.merge(acc.rejected, g.rejected, fn _, a, b -> a + b end)
      }
    end)
  end

  @doc "Diferença entre duas leituras de fofoca (depois menos antes)."
  @spec gossip_delta(map(), map()) :: map()
  def gossip_delta(a, b) do
    %{
      ok: b.ok - a.ok,
      duplicate: b.duplicate - a.duplicate,
      rejected:
        for({k, n} <- b.rejected, d = n - Map.get(a.rejected, k, 0), d > 0, into: %{}, do: {k, d})
    }
  end

  defp blocks_between(_eps, h0, h1) when h1 <= h0,
    do: %{count: 0, tx: 0, per_block: 0.0, interval_s: nil}

  defp blocks_between(eps, h0, h1) do
    {:ok, rows} = Client.blocks(hd(eps), h1 + 1, min(100, h1 - h0))
    rows = Enum.filter(rows, &(&1.height > h0))
    tx = rows |> Enum.map(& &1.tx_count) |> Enum.sum()
    times = rows |> Enum.map(& &1.time) |> Enum.sort()
    span = if length(times) > 1, do: List.last(times) - hd(times), else: nil

    %{
      count: h1 - h0,
      tx: tx,
      per_block: Float.round(tx / max(length(rows), 1), 1),
      interval_s: if(span, do: Float.round(span / (length(times) - 1), 2), else: nil)
    }
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp wait_until(fun, ms) do
    deadline = now_ms() + ms

    Stream.repeatedly(fn -> fun.() || (now_ms() < deadline && Process.sleep(150) && :again) end)
    |> Enum.find(&(&1 != :again))
  end
end
