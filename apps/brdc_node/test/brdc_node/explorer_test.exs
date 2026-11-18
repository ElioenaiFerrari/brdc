defmodule BrdcNode.ExplorerTest do
  # consultas do explorador pela porta pública: blocos, transações, histórico, pendentes, e a CONFERÊNCIA do certificado
  use ExUnit.Case, async: false
  alias BrdcConsensus.{Certificate, Vote}
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Block, Tx}
  alias BrdcNode.{Client, Genesis, Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @moduletag :tmp_dir
  @chain "explorer-test"

  defp seed(n), do: :crypto.hash(:sha256, "explorer-#{n}")
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

  defp mint_tx(to, amount, ref, nonce) do
    d = Tx.issuance_doc(:mint, @chain, addr(to), amount, ref)
    approvals = for i <- [10, 11], do: Tx.approval(d, seed(i))

    %Tx{
      chain_id: @chain,
      kind: 2,
      nonce: nonce,
      fee: 0,
      sender_pub: pub(50),
      payload: Tx.issuance_payload(addr(to), amount, ref, approvals)
    }
    |> Tx.sign(seed(50))
  end

  defp cert(block, signers) do
    votes =
      for n <- signers,
          do: Vote.sign(@chain, :precommit, block.height, 0, Block.hash(block), seed(n))

    %Certificate{height: block.height, round: 0, block_hash: Block.hash(block), votes: votes}
  end

  defp start_node(dir) do
    {:ok, node} =
      Node.start_link(
        genesis: genesis(),
        seed: seed(1),
        block_interval_ms: :manual,
        clock: fn -> 1_000 end,
        data_dir: dir
      )

    node
  end

  defp commit(node, tx, signers \\ [1, 2, 3]) do
    {:ok, _} = Node.submit(node, Tx.encode(tx))
    {:ok, block} = Node.build_proposal(node)
    {:ok, _} = Node.commit_block(node, block, cert(block, signers))
    block
  end

  defp serve(node) do
    {:ok, guard} = Guard.start_link(sweep_ms: :never)
    {:ok, port} = PublicPort.start_link(guard: guard, handler: Handler.fun(node), port: 0)
    on_exit(fn -> catch_exit(PublicPort.stop(port)) end)
    {~c"127.0.0.1", PublicPort.port(port)}
  end

  setup %{tmp_dir: dir} do
    node = start_node(dir)
    b1 = commit(node, mint_tx(51, 5_000_000, "r1", 0))
    b2 = commit(node, mint_tx(52, 2_000_000, "r2", 1))
    %{node: node, ep: serve(node), b1: b1, b2: b2, dir: dir}
  end

  test "blocos: do mais novo ao mais antigo, com paginação e contagem de assinantes", %{
    ep: ep,
    b1: b1,
    b2: b2
  } do
    assert {:ok, [two, one]} = Client.blocks(ep)
    assert {two.height, one.height} == {2, 1}
    assert two.hash == Block.hash(b2) and one.hash == Block.hash(b1)
    assert two.tx_count == 1 and two.signers == 3
    assert two.proposer == addr(1)

    assert {:ok, [only]} = Client.blocks(ep, 2, 5)
    assert only.height == 1
    assert {:ok, []} = Client.blocks(ep, 1, 5)
  end

  test "bloco com certificado conferido: fixando as chaves da gênese a confiança é total", %{
    ep: ep,
    b1: b1
  } do
    pins = Enum.map(1..4, &pub/1)
    assert {:ok, r} = Client.block(ep, 1, pins)
    assert r.verified and r.trust == :pinned and r.reason == nil
    assert r.hash == Block.hash(b1)
    assert length(Certificate.signers(r.certificate)) == 3

    # sem fixar, usa as chaves que o nó informa: prova só a consistência interna
    assert {:ok, %{verified: true, trust: :node_reported}} = Client.block(ep, 1)
  end

  test "um nó que mente sobre os validadores NÃO engana quem fixou as chaves da gênese", %{ep: ep} do
    outras = Enum.map(31..34, &pub/1)
    assert {:ok, r} = Client.block(ep, 1, outras)
    refute r.verified
    assert r.reason != nil
  end

  test "quórum fraco: 3 assinaturas não chegam a 2/3 de 6 validadores fixados, então NÃO é conferido",
       %{ep: ep} do
    seis = Enum.map(1..6, &pub/1)
    assert {:ok, r} = Client.block(ep, 1, seis)
    refute r.verified
    assert r.reason != nil
  end

  test "altura que não existe dá not_found", %{ep: ep} do
    assert {:error, "not_found"} = Client.block(ep, 9)
  end

  test "transação pelo id: a transação, o bloco e a posição; id desconhecido dá not_found", %{
    ep: ep,
    b2: b2
  } do
    id = Tx.id(hd(b2.txs))
    assert {:ok, r} = Client.tx(ep, id)
    assert {r.height, r.index} == {2, 0}
    assert r.block_hash == Block.hash(b2)
    assert Tx.id(r.tx) == id

    assert {:error, "not_found"} = Client.tx(ep, :crypto.hash(:sha256, "nao existe"))
  end

  test "histórico da conta: remetente e destinatário, do mais novo ao mais antigo", %{ep: ep} do
    assert {:ok, [b, a]} = Client.account_history(ep, addr(50))
    assert {b.height, a.height} == {2, 1}
    assert Enum.all?([a, b], &(&1.role == :sender and &1.kind == 2))

    assert {:ok, [r]} = Client.account_history(ep, addr(51))
    assert r.role == :receiver and r.height == 1
    assert {:ok, []} = Client.account_history(ep, addr(99))
  end

  test "pendentes: a transação aparece no mempool até virar bloco", %{node: node, ep: ep} do
    assert {:ok, []} = Client.mempool(ep)
    tx = mint_tx(54, 1_000_000, "r4", 2)
    {:ok, _} = Node.submit(node, Tx.encode(tx))

    assert {:ok, [m]} = Client.mempool(ep)
    assert m.id == Tx.id(tx)
  end

  test "o índice é reconstruído do disco ao reiniciar", %{node: node, dir: dir, b2: b2} do
    GenServer.stop(node)
    node2 = start_node(dir)
    ep2 = serve(node2)

    assert {:ok, %{height: 2}} = Client.tx(ep2, Tx.id(hd(b2.txs)))
    assert {:ok, [_, _]} = Client.account_history(ep2, addr(50))
    assert {:ok, %{verified: true}} = Client.block(ep2, 2, Enum.map(1..4, &pub/1))
  end

  test "validadores: as chaves em vigor", %{ep: ep} do
    assert {:ok, pubs} = Client.validators(ep)
    assert Enum.sort(pubs) == Enum.sort(Enum.map(1..4, &pub/1))
  end
end
