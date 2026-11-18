defmodule BrdcNode.MultiCommitTest do
  use ExUnit.Case, async: true
  alias BrdcConsensus.{Certificate, Vote}
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Block, State, Tx}
  alias BrdcNode.{Genesis, Node}

  @moduletag :tmp_dir
  @chain "multi-test"

  defp seed(n), do: :crypto.hash(:sha256, "multi-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  # validadores 1-4 · emissores 10-11 · autoridades 20-21 · contas 50-51
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

  defp start_nodes(dir, clock \\ fn -> 1_000 end) do
    for n <- 1..4 do
      {:ok, node} =
        Node.start_link(
          genesis: genesis(),
          seed: seed(n),
          block_interval_ms: :manual,
          clock: clock,
          data_dir: Path.join(dir, "n#{n}")
        )

      node
    end
  end

  defp mint_tx(to, amount, ref) do
    d = Tx.issuance_doc(:mint, @chain, addr(to), amount, ref)
    approvals = for i <- [10, 11], do: Tx.approval(d, seed(i))

    Tx.sign(
      %Tx{
        chain_id: @chain,
        kind: 2,
        nonce: 0,
        fee: 0,
        sender_pub: pub(50),
        payload: Tx.issuance_payload(addr(to), amount, ref, approvals)
      },
      seed(50)
    )
    |> Tx.encode()
  end

  # certificado de commit: precommits de `signers` (índices de validador) no bloco
  defp cert(block, signers, round \\ 0) do
    votes =
      for n <- signers,
          do: Vote.sign(@chain, :precommit, block.height, round, Block.hash(block), seed(n))

    %Certificate{height: block.height, round: round, block_hash: Block.hash(block), votes: votes}
  end

  defp root(node), do: State.root(:sys.get_state(node).state)
  defp height(node), do: :sys.get_state(node).state.height

  defp first_block(nodes, txs) do
    [a | _] = nodes
    for t <- txs, do: {:ok, _} = Node.submit(a, t)
    {:ok, block} = Node.build_proposal(a)
    block
  end

  test "o cabeçalho leva o conjunto de validadores como signers; todos conferem e confirmam o mesmo bloco",
       %{tmp_dir: dir} do
    nodes = start_nodes(dir)
    block = first_block(nodes, [mint_tx(51, 5_000_000, "r1")])
    assert block.signers == Enum.sort(Enum.map(1..4, &addr/1))
    assert block.proposer == addr(1)

    for n <- nodes, do: assert(Node.check_block(n, block, 1_000) == :ok)
    c = cert(block, [1, 2, 3])
    for n <- nodes, do: assert({:ok, 1} = Node.commit_block(n, block, c))

    assert nodes |> Enum.map(&root/1) |> Enum.uniq() |> length() == 1
    assert Enum.all?(nodes, &(height(&1) == 1))
    # a taxa foi repartida entre os 4 validadores (a mint tem taxa 0; o saldo vem do mint)
    assert Node.account(hd(nodes), addr(51)).balance == 5_000_000
  end

  test "o certificado vai para o disco junto do bloco e volta ao reiniciar (e serve à sincronização)",
       %{tmp_dir: dir} do
    nodes = start_nodes(dir)
    block = first_block(nodes, [mint_tx(51, 1_000_000, "r1")])
    c = cert(block, [2, 3, 4])
    for n <- nodes, do: {:ok, 1} = Node.commit_block(n, block, c)
    assert [{^block, ^c}] = Node.blocks_from(hd(nodes), 1, 10)
    GenServer.stop(hd(nodes))

    {:ok, again} =
      Node.start_link(
        genesis: genesis(),
        seed: seed(1),
        block_interval_ms: :manual,
        clock: fn -> 1_000 end,
        data_dir: Path.join(dir, "n1")
      )

    assert height(again) == 1
    assert [{^block, got}] = Node.blocks_from(again, 1, 10)
    assert got == c
    assert Certificate.verify(got, @chain, Enum.map(1..4, &pub/1)) == :ok
  end

  test "certificado ruim é recusado e o estado não muda", %{tmp_dir: dir} do
    [a | _] = nodes = start_nodes(dir)
    block = first_block(nodes, [mint_tx(51, 1_000_000, "r1")])
    other = first_block(start_nodes(Path.join(dir, "x")), [mint_tx(51, 2_000_000, "r2")])

    # sem quórum (2 de 4), voto repetido, estranho ao conjunto, assinatura de outro bloco, hash trocado, altura trocada
    assert {:error, :no_quorum} = Node.commit_block(a, block, cert(block, [1, 2]))
    assert {:error, :duplicate_voter} = Node.commit_block(a, block, cert(block, [1, 1, 2, 3]))
    assert {:error, :unknown_voter} = Node.commit_block(a, block, cert(block, [1, 2, 3, 30]))
    assert {:error, :cert_hash_mismatch} = Node.commit_block(a, block, cert(other, [1, 2, 3]))

    assert {:error, :cert_height_mismatch} =
             Node.commit_block(a, block, %{cert(block, [1, 2, 3]) | height: 9})

    assert {:error, :cert_hash_mismatch} = Node.commit_block(a, block, nil)
    forged = cert(block, [1, 2, 3])
    bad_sig = %{hd(forged.votes) | signature: :binary.copy(<<1>>, 64)}

    assert {:error, :bad_signature} =
             Node.commit_block(a, block, %{forged | votes: [bad_sig | tl(forged.votes)]})

    assert height(a) == 0
  end

  test "bloco com signers errados ou horário implausível não passa na conferência", %{
    tmp_dir: dir
  } do
    [a | _] = nodes = start_nodes(dir)
    block = first_block(nodes, [mint_tx(51, 1_000_000, "r1")])

    assert {:error, :bad_signers} = Node.check_block(a, %{block | signers: [addr(1)]}, 1_000)
    # 1.000 s vs relógio local em 100 s: bloco do futuro além da tolerância
    assert {:error, :implausible_time} = Node.check_block(a, block, 100)
    # raiz de estado adulterada
    assert {:error, :bad_state_root} =
             Node.check_block(a, %{block | state_root: :crypto.hash(:sha256, "x")}, 1_000)

    assert height(a) == 0
  end

  test "confirmar duas vezes o mesmo bloco é idempotente; outro bloco na mesma altura é recusado",
       %{tmp_dir: dir} do
    [a | _] = nodes = start_nodes(dir)
    block = first_block(nodes, [mint_tx(51, 1_000_000, "r1")])
    c = cert(block, [1, 2, 3])
    assert {:ok, 1} = Node.commit_block(a, block, c)
    assert {:ok, 1} = Node.commit_block(a, block, c)
    assert height(a) == 1

    other = first_block(start_nodes(Path.join(dir, "y")), [mint_tx(51, 7_000_000, "r9")])
    assert {:error, :conflicting_block} = Node.commit_block(a, other, cert(other, [1, 2, 3]))
  end

  test "bloco do futuro (altura pulada) é recusado", %{tmp_dir: dir} do
    [a | _] = nodes = start_nodes(dir)
    block = first_block(nodes, [mint_tx(51, 1_000_000, "r1")])
    skipped = %{block | height: 5}
    assert {:error, _} = Node.commit_block(a, skipped, cert(skipped, [1, 2, 3]))
    assert height(a) == 0
  end

  test "ao confirmar, o mempool perde as transações incluídas e as que ficaram inválidas", %{
    tmp_dir: dir
  } do
    [a, b | _] = nodes = start_nodes(dir)
    t1 = mint_tx(51, 1_000_000, "r1")
    {:ok, _} = Node.submit(a, t1)
    {:ok, _} = Node.submit(b, t1)
    {:ok, block} = Node.build_proposal(a)
    c = cert(block, [1, 2, 3])
    for n <- nodes, do: {:ok, 1} = Node.commit_block(n, block, c)
    # nada sobra para propor: o mempool dos dois esvaziou
    assert Node.build_proposal(a) == :nothing
    assert Node.build_proposal(b) == :nothing
    assert Node.status(a).pending == 0
  end

  test "o gancho de transações avisa só das novas (para espalhar aos pares)", %{tmp_dir: dir} do
    [a | _] = start_nodes(dir)
    :ok = Node.set_tx_hook(a, self())
    t = mint_tx(51, 1_000_000, "r1")
    {:ok, _} = Node.submit(a, t)
    assert_receive {:brdc_tx, ^t}
    assert {:error, :duplicate} = Node.submit(a, t)
    refute_receive {:brdc_tx, _}, 50
  end

  test "certificado: ida e volta e recusa de lixo" do
    {:ok, g} = {:ok, genesis()}
    assert length(g.validators) == 4

    block = %Block{
      height: 1,
      time: 1,
      prev_hash: nil,
      proposer: addr(1),
      signers: [addr(1)],
      txs: [],
      state_root: :crypto.hash(:sha256, "r")
    }

    c = cert(block, [1, 2, 3])
    assert {:ok, ^c} = Certificate.decode(Certificate.encode(c))
    bin = Certificate.encode(c)
    assert {:error, :malformed} = Certificate.decode(bin <> <<0>>)
    assert {:error, :malformed} = Certificate.decode(binary_part(bin, 0, 50))
    assert {:error, :malformed} = Certificate.decode("lixo")
  end
end
