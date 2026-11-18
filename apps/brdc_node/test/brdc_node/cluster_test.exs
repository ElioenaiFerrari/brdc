defmodule BrdcNode.ClusterTest do
  # 4 validadores na mesma VM, em TCP/TLS real (loopback), cada um com nó, réplica, disco e diário
  use ExUnit.Case, async: false
  alias BrdcConsensus.Certificate
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{State, Tx}
  alias BrdcNode.{Client, Genesis, Handler, Node, Replica}
  alias BrdcP2p.{Guard, PublicPort}

  @moduletag :tmp_dir
  @moduletag timeout: 120_000
  @chain "cluster-test"

  defp seed(n), do: :crypto.hash(:sha256, "cluster-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  defp genesis do
    {:ok, g} =
      Genesis.new(
        chain_id: @chain,
        validators: Enum.map(1..4, &pub/1),
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2,
        min_window: 1
      )

    g
  end

  defp free_port do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)
    port
  end

  # sobe (ou resobe) o validador `i`; `ctx` = %{dir, ports}
  defp start_validator(ctx, i) do
    dir = Path.join(ctx.dir, "v#{i}")

    {:ok, node} =
      Node.start_link(
        genesis: genesis(),
        seed: seed(i),
        block_interval_ms: :manual,
        data_dir: dir
      )

    peers = for j <- 1..4, j != i, do: %{pub: pub(j), host: "127.0.0.1", port: ctx.ports[j]}

    {:ok, replica} =
      Replica.start_link(
        node: node,
        genesis: genesis(),
        seed: seed(i),
        data_dir: dir,
        port: ctx.ports[i],
        peers: peers,
        interval_ms: 50,
        timeouts: %{propose: 600, prevote: 300, precommit: 300, delta: 200}
      )

    %{node: node, replica: replica}
  end

  defp stop_validator(%{node: node, replica: replica}) do
    GenServer.stop(replica)
    GenServer.stop(node)
  end

  defp cluster(%{tmp_dir: dir}, which \\ 1..4) do
    ctx = %{dir: dir, ports: Map.new(1..4, &{&1, free_port()})}
    {ctx, Map.new(which, &{&1, start_validator(ctx, &1)})}
  end

  defp mint(sender, to, amount, ref) do
    d = Tx.issuance_doc(:mint, @chain, addr(to), amount, ref)
    approvals = for i <- [10, 11], do: Tx.approval(d, seed(i))

    %Tx{
      chain_id: @chain,
      kind: 2,
      nonce: 0,
      fee: 0,
      sender_pub: pub(sender),
      payload: Tx.issuance_payload(addr(to), amount, ref, approvals)
    }
    |> Tx.sign(seed(sender))
    |> Tx.encode()
  end

  defp state(%{node: n}), do: :sys.get_state(n).state
  defp height(v), do: state(v).height
  defp root(v), do: State.root(state(v))

  defp await(fun, ms \\ 15_000) do
    deadline = System.monotonic_time(:millisecond) + ms
    do_await(fun, deadline)
  end

  defp do_await(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("a condição não ficou verdadeira a tempo")

      true ->
        Process.sleep(25) && do_await(fun, deadline)
    end
  end

  defp all_at(vs, h), do: Enum.all?(vs, &(height(&1) >= h))

  defp same_state?(vs),
    do: vs |> Enum.map(&{height(&1), root(&1)}) |> Enum.uniq() |> length() == 1

  defp connected?(vs),
    do: Enum.all?(vs, &(length(Replica.connected(&1.replica)) == length(vs) - 1))

  test "uma transação enviada a UM nó vira bloco em todos, com certificado de mais de 2/3", ctx do
    {_c, vs} = cluster(ctx)
    vs = Map.values(vs)
    await(fn -> connected?(vs) end)

    {:ok, _} = Node.submit(hd(vs).node, mint(50, 51, 5_000_000, "r1"))
    await(fn -> all_at(vs, 1) and same_state?(vs) end)

    for v <- vs do
      assert Node.account(v.node, addr(51)).balance == 5_000_000
      assert [{block, cert}] = Node.blocks_from(v.node, 1, 5)
      assert Certificate.verify(cert, @chain, genesis().validators) == :ok
      assert cert.block_hash == BrdcLedger.Block.hash(block)
      assert length(Certificate.signers(cert)) >= 3
    end

    # sem transação pendente, a rede fica parada: nada de bloco vazio
    Process.sleep(1_000)
    assert Enum.all?(vs, &(height(&1) == 1))
    assert Enum.all?(vs, &(Replica.info(&1.replica).engine == nil))
  end

  test "transações enviadas a nós diferentes ao mesmo tempo: mesmo estado final em todos, sem equivocação",
       ctx do
    {_c, vs} = cluster(ctx)
    list = Map.values(vs)
    await(fn -> connected?(list) end)

    for {i, sender} <- Enum.zip(1..4, 50..53) do
      {:ok, _} = Node.submit(vs[i].node, mint(sender, 60 + i, 1_000_000 * i, "ref-#{i}"))
    end

    await(fn ->
      Enum.all?(list, &(State.supply(state(&1)) == 10_000_000)) and same_state?(list)
    end)

    assert Enum.all?(list, &(Replica.info(&1.replica).evidence == 0))
  end

  test "o proponente da rodada 0 fora do ar: outro assume; quando ele volta, sincroniza", ctx do
    {c, vs} = cluster(ctx)
    await(fn -> connected?(Map.values(vs)) end)

    # altura 1, rodada 0: proponente = validador de índice 1 (o nº 2)
    stop_validator(vs[2])
    up = [vs[1], vs[3], vs[4]]
    await(fn -> Enum.all?(up, &(length(Replica.connected(&1.replica)) == 2)) end)

    {:ok, _} = Node.submit(vs[1].node, mint(50, 51, 2_000_000, "r1"))
    await(fn -> all_at(up, 1) and same_state?(up) end, 20_000)

    # o nº 2 volta (mesmo disco, mesma porta) e se atualiza pela sincronização
    v2 = start_validator(c, 2)
    await(fn -> height(v2) == 1 and same_state?([v2 | up]) end, 20_000)
  end

  test "perdendo o quórum (2 de 4 fora) a rede PARA em vez de bifurcar; ao voltar um, retoma",
       ctx do
    {c, vs} = cluster(ctx)
    await(fn -> connected?(Map.values(vs)) end)

    stop_validator(vs[3])
    stop_validator(vs[4])
    up = [vs[1], vs[2]]
    await(fn -> Enum.all?(up, &(length(Replica.connected(&1.replica)) == 1)) end)

    {:ok, _} = Node.submit(vs[1].node, mint(50, 51, 1_000_000, "r1"))
    Process.sleep(3_000)
    assert Enum.all?(up, &(height(&1) == 0))

    v3 = start_validator(c, 3)
    all = [vs[1], vs[2], v3]

    await(fn -> all_at(all, 1) and same_state?(all) end, 25_000)
  end

  test "um validador entra tarde (depois de vários blocos) e se atualiza conferindo os certificados",
       ctx do
    {c, vs} = cluster(ctx, 1..3)
    up = Map.values(vs)
    await(fn -> Enum.all?(up, &(length(Replica.connected(&1.replica)) == 2)) end)

    for k <- 1..5 do
      {:ok, _} =
        Node.submit(vs[rem(k, 3) + 1].node, mint(50 + k, 60 + k, 100_000 * k, "blk-#{k}"))

      await(fn -> all_at(up, k) end, 20_000)
    end

    late = start_validator(c, 4)
    await(fn -> height(late) == 5 and same_state?([late | up]) end, 25_000)
    # os blocos que ele guardou têm certificado válido
    for {_b, cert} <- Node.blocks_from(late.node, 1, 10) do
      assert Certificate.verify(cert, @chain, genesis().validators) == :ok
    end
  end

  test "muitas transações em rajada, em nós diferentes: todas entram e o estado é idêntico",
       ctx do
    {_c, vs} = cluster(ctx)
    list = Map.values(vs)
    await(fn -> connected?(list) end)

    for k <- 1..24 do
      {:ok, _} = Node.submit(vs[rem(k, 4) + 1].node, mint(100 + k, 200 + k, 10_000, "burst-#{k}"))
    end

    await(
      fn -> Enum.all?(list, &(State.supply(state(&1)) == 240_000)) and same_state?(list) end,
      30_000
    )

    assert Enum.all?(list, &(Replica.info(&1.replica).evidence == 0))
  end

  test "um validador reinicia no meio (mesmo disco e diário) e a rede segue consistente", ctx do
    {c, vs} = cluster(ctx)
    list = Map.values(vs)
    await(fn -> connected?(list) end)
    {:ok, _} = Node.submit(vs[1].node, mint(50, 51, 1_000_000, "a"))
    await(fn -> all_at(list, 1) end)

    stop_validator(vs[3])
    v3 = start_validator(c, 3)
    all = [vs[1], vs[2], v3, vs[4]]
    await(fn -> connected?(all) end)
    assert height(v3) == 1

    {:ok, _} = Node.submit(v3.node, mint(52, 53, 2_000_000, "b"))
    await(fn -> all_at(all, 2) and same_state?(all) end)
  end

  test "a carteira (porta pública) conversa com QUALQUER nó: a transação entra e vira bloco em todos",
       ctx do
    {_c, vs} = cluster(ctx)
    list = Map.values(vs)
    await(fn -> connected?(list) end)

    {:ok, guard} = Guard.start_link(sweep_ms: :never)

    {:ok, port_pid} =
      PublicPort.start_link(guard: guard, handler: Handler.fun(vs[3].node), port: 0)

    on_exit(fn -> catch_exit(PublicPort.stop(port_pid)) end)
    endpoint = {~c"127.0.0.1", PublicPort.port(port_pid)}

    assert {:ok, _} = Client.submit_tx(endpoint, mint(50, 51, 3_000_000, "via-carteira"))
    await(fn -> all_at(list, 1) and same_state?(list) end)
    assert {:ok, acc} = Client.account(endpoint, addr(51))
    assert acc.balance == 3_000_000
  end
end
