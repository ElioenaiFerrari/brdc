defmodule BrdcNode.NodeTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{State, Tx}
  alias BrdcNode.{Genesis, Handler, Node}

  defp seed(n), do: :crypto.hash(:sha256, "node-seed-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  defp genesis do
    {:ok, g} =
      Genesis.new(
        chain_id: "node-test",
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        min_window: 1
      )

    g
  end

  defp start(opts \\ []) do
    {:ok, clock} = Agent.start_link(fn -> 1_000 end)

    {:ok, node} =
      Node.start_link(
        Keyword.merge(
          [
            genesis: genesis(),
            seed: seed(1),
            block_interval_ms: :manual,
            clock: fn -> Agent.get(clock, & &1) end
          ],
          opts
        )
      )

    {node, clock}
  end

  defp signed(node, n, kind, payload, fee \\ nil) do
    nonce = Node.account(node, addr(n), pending: true).nonce

    t = %Tx{
      chain_id: "node-test",
      kind: kind,
      nonce: nonce,
      fee: 0,
      sender_pub: pub(n),
      payload: payload
    }

    st =
      State.new(
        BrdcLedger.Params.new(chain_id: "node-test", issuers: [pub(10)], threshold: 1)
        |> elem(1)
      )

    fee = fee || BrdcLedger.Executor.min_fee(st.params, t)
    Tx.sign(%{t | fee: fee}, seed(n))
  end

  defp mint(node, to_n, amount, ref) do
    d = Tx.issuance_doc(:mint, "node-test", addr(to_n), amount, ref)
    ap = for i <- [10, 11], do: Tx.approval(d, seed(i))
    signed(node, 99, 2, Tx.issuance_payload(addr(to_n), amount, ref, ap), 0)
  end

  defp transfer(node, from, to, amount) do
    signed(node, from, 1, Tx.transfer_payload(addr(to), amount))
  end

  defp submit(node, tx), do: Node.submit(node, Tx.encode(tx))

  test "começa na gênese, sem blocos, com a tabela de taxas" do
    {node, _} = start()
    s = Node.status(node)
    assert %{chain_id: "node-test", height: 0, supply: 0, pending: 0, last_hash: nil} = s
    assert s.transfer_base == 1_000 and s.per_byte == 1
    assert Node.account(node, addr(5)) == %{balance: 0, nonce: 0}
    assert Node.produce(node) == :nothing
  end

  test "mint, bloco, transferência: saldo muda só depois do bloco; o pendente já aparece" do
    {node, clock} = start()
    {:ok, _} = submit(node, mint(node, 5, 5_000_000, "dep-1"))
    assert Node.status(node).pending == 1
    assert Node.account(node, addr(5)).balance == 0
    assert Node.account(node, addr(5), pending: true).balance == 5_000_000

    Agent.update(clock, fn _ -> 1_050 end)
    assert {:ok, 1} = Node.produce(node)
    assert Node.account(node, addr(5)).balance == 5_000_000

    assert Node.status(node) |> Map.take([:height, :time, :supply, :pending]) == %{
             height: 1,
             time: 1_050,
             supply: 5_000_000,
             pending: 0
           }

    {:ok, _} = submit(node, transfer(node, 5, 6, 1_000_000))
    assert {:ok, 2} = Node.produce(node)
    assert Node.account(node, addr(6)).balance == 1_000_000
    # a taxa foi para o validador (conta 1)
    assert Node.account(node, addr(1)).balance > 0
    assert Node.account(node, addr(5)).nonce == 1
  end

  test "sem transação pendente não há bloco (nunca bloco vazio)" do
    {node, _} = start()
    assert Node.produce(node) == :nothing
    assert Node.status(node).height == 0
  end

  test "transação inválida é recusada na entrada e não entra no mempool" do
    {node, _} = start()
    {:ok, _} = submit(node, mint(node, 5, 1_000_000, "dep-1"))
    {:ok, 1} = Node.produce(node) |> then(&{:ok, elem(&1, 1)})

    assert {:error, :insufficient_funds} = submit(node, transfer(node, 5, 6, 50_000_000))

    assert {:error, :fee_too_low} =
             submit(node, signed(node, 5, 1, Tx.transfer_payload(addr(6), 1), 10))

    assert {:error, :malformed} = Node.submit(node, "lixo")

    assert {:error, :bad_signature} =
             Node.submit(node, Tx.encode(%{transfer(node, 5, 6, 1) | fee: 99_999}))

    assert Node.status(node).pending == 0
  end

  test "mesma transação duas vezes: recusada; nonce em sequência dentro do mesmo bloco" do
    {node, _} = start()
    {:ok, _} = submit(node, mint(node, 5, 10_000_000, "dep-1"))
    {:ok, _} = Node.produce(node) |> then(&{:ok, &1})

    t1 = transfer(node, 5, 6, 1_000)
    assert {:ok, _} = submit(node, t1)
    assert {:error, :duplicate} = submit(node, t1)
    t2 = transfer(node, 5, 6, 2_000)
    assert t2.nonce == 1
    assert {:ok, _} = submit(node, t2)
    assert Node.status(node).pending == 2

    assert {:ok, 2} = Node.produce(node)
    assert Node.account(node, addr(6)).balance == 3_000
    assert Node.status(node).pending == 0
  end

  test "mint repetido (mesma referência) é recusado mesmo pendente; só com as aprovações dos emissores" do
    {node, _} = start()
    {:ok, _} = submit(node, mint(node, 5, 1_000_000, "dep-1"))
    assert {:error, :ref_used} = submit(node, mint(node, 5, 1_000_000, "dep-1"))

    d = Tx.issuance_doc(:mint, "node-test", addr(5), 1_000_000, "dep-2")

    forged =
      signed(
        node,
        99,
        2,
        Tx.issuance_payload(addr(5), 1_000_000, "dep-2", [Tx.approval(d, seed(10))]),
        0
      )

    assert {:error, :not_enough_approvals} = submit(node, forged)
  end

  test "o horário do bloco nunca decresce, mesmo com o relógio voltando" do
    {node, clock} = start()
    {:ok, _} = submit(node, mint(node, 5, 5_000_000, "a"))
    Agent.update(clock, fn _ -> 2_000 end)
    {:ok, 1} = Node.produce(node) |> then(&{:ok, elem(&1, 1)})
    {:ok, _} = submit(node, mint(node, 5, 5_000_000, "b"))
    Agent.update(clock, fn _ -> 1_500 end)
    assert {:ok, 2} = Node.produce(node)
    assert Node.status(node).time == 2_000
  end

  test "o bloco é consultável e inscritos recebem aviso de cada bloco" do
    {node, _} = start()
    :ok = Node.subscribe(node)
    {:ok, id} = submit(node, mint(node, 5, 5_000_000, "a"))
    {:ok, 1} = Node.produce(node) |> then(&{:ok, elem(&1, 1)})
    assert_receive {:brdc_block, 1, [^id]}
    assert {:ok, block} = Node.block(node, 1)
    assert block.height == 1 and length(block.txs) == 1
    assert :error = Node.block(node, 2)
  end

  test "com relógio automático, o bloco sai sozinho depois do intervalo (e só então)" do
    {node, _} = start(block_interval_ms: 30)
    :ok = Node.subscribe(node)
    {:ok, _} = submit(node, mint(node, 5, 5_000_000, "a"))
    refute_received {:brdc_block, _, _}
    assert_receive {:brdc_block, 1, _}, 1_000
    # depois disso, sem pendentes, nada mais é produzido
    refute_receive {:brdc_block, _, _}, 150
  end

  test "respeita o limite de transações por bloco: o resto fica para o seguinte" do
    {:ok, g} =
      Genesis.new(
        chain_id: "node-test",
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        min_window: 1,
        max_block_txs: 2
      )

    {node, _} = start(genesis: g)
    for i <- 1..5, do: {:ok, _} = submit(node, mint(node, 5, 1_000_000, "r#{i}"))
    assert Node.status(node).pending == 5
    {:ok, 1} = Node.produce(node) |> then(&{:ok, elem(&1, 1)})
    assert Node.status(node).pending == 3
    {:ok, 2} = Node.produce(node) |> then(&{:ok, elem(&1, 1)})
    {:ok, 3} = Node.produce(node) |> then(&{:ok, elem(&1, 1)})
    assert Node.status(node).pending == 0
    assert Node.account(node, addr(5)).balance == 5_000_000
  end

  describe "ponte para a porta pública" do
    test "status, conta e envio com respostas em codificação determinística" do
      {node, _} = start()
      f = Handler.fun(node)

      assert {:ok, bin} = f.(:status, <<>>)

      assert {:ok, ["node-test", 0, 0, 0, <<>>, 0, 1_000, 1, 10_000]} =
               BrdcCrypto.Encoding.decode(Handler.status_schema(), bin)

      assert {:ok, bin} = f.(:get_account, addr(5))
      assert {:ok, [0, 0, 0, 0]} = BrdcCrypto.Encoding.decode(Handler.account_schema(), bin)
      assert {:error, :bad_address} = f.(:get_account, "curto")

      tx = mint(node, 5, 5_000_000, "dep")
      assert {:ok, id} = f.(:submit_tx, Tx.encode(tx))
      assert id == Tx.id(tx)
      assert {:error, :duplicate} = f.(:submit_tx, Tx.encode(tx))
      assert {:error, :unsupported} = f.(:get_block, <<0::64>>)
    end
  end
end
