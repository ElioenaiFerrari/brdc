defmodule BrdcNode.PersistenceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Approvals, Assets, Block, State, Tx}
  alias BrdcNode.BlockStore.File, as: LogFile
  alias BrdcNode.{Genesis, Node}

  @moduletag :tmp_dir

  defp seed(n), do: :crypto.hash(:sha256, "persist-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  defp genesis(chain \\ "persist-test") do
    {:ok, g} =
      Genesis.new(
        chain_id: chain,
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2,
        min_window: 1
      )

    g
  end

  defp start(dir, opts \\ []) do
    Node.start_link(
      Keyword.merge(
        [
          genesis: genesis(),
          seed: seed(1),
          block_interval_ms: :manual,
          clock: fn -> 1_000 end,
          data_dir: dir
        ],
        opts
      )
    )
  end

  defp signed(node, n, kind, payload, fee) do
    nonce = Node.account(node, addr(n), pending: true).nonce

    Tx.sign(
      %Tx{
        chain_id: "persist-test",
        kind: kind,
        nonce: nonce,
        fee: fee,
        sender_pub: pub(n),
        payload: payload
      },
      seed(n)
    )
  end

  defp run(node, n, kind, payload, fee \\ 0) do
    {:ok, _} = Node.submit(node, Tx.encode(signed(node, n, kind, payload, fee)))
    Node.produce(node)
  end

  defp mint(node, n, amount, ref) do
    d = Tx.issuance_doc(:mint, "persist-test", addr(n), amount, ref)

    run(
      node,
      99,
      2,
      Tx.issuance_payload(addr(n), amount, ref, for(i <- [10, 11], do: Tx.approval(d, seed(i))))
    )
  end

  # monta uma história com saldos, classe, bem, credencial e proposta aberta
  defp history(node) do
    mint(node, 50, 10_000_000, "a")
    mint(node, 99, 10_000_000, "b")
    run(node, 50, 1, Tx.transfer_payload(addr(51), 2_500_000), 5_000)

    organ = [pub(30)]
    cd = Assets.class_doc("persist-test", "imovel", organ, 1, 60)

    run(
      node,
      99,
      5,
      Assets.class_payload(
        "imovel",
        organ,
        1,
        60,
        for(i <- [20, 21], do: Approvals.approval(cd, seed(i)))
      ),
      50_000
    )

    rd = Assets.register_doc("persist-test", "imovel", "casa-1", addr(50), "Rua A")

    run(
      node,
      99,
      6,
      Assets.register_payload("imovel", "casa-1", addr(50), "Rua A", [
        Approvals.approval(rd, seed(30))
      ]),
      50_000
    )

    # proposta aberta (não vira bloco): veto de credencial inexistente não vale, então uma de gravame
    {:ok, _} = Node.propose(node, :lien_add, %{asset: "casa-1", lien: "g1", ref: "r"})
  end

  defp snapshot(node) do
    st = :sys.get_state(node).state
    %{root: State.root(st), height: st.height, last_hash: st.last_hash, time: st.time}
  end

  test "reiniciar o nó preserva saldos, bens, classes, altura e raiz de estado", %{tmp_dir: dir} do
    {:ok, node} = start(dir)
    history(node)
    before = snapshot(node)
    assert before.height == 5
    GenServer.stop(node)

    {:ok, node2} = start(dir)
    assert snapshot(node2) == before
    assert Node.account(node2, addr(51)).balance == 2_500_000
    assert [%{id: "casa-1", role: "owner"}] = Node.assets_of(node2, addr(50))
    # a história continua: o próximo bloco é o 6 e encadeia no último
    mint(node2, 51, 1_000_000, "c")
    assert snapshot(node2).height == 6
  end

  test "as propostas dos órgãos sobrevivem ao reinício, conferidas de novo contra o estado", %{
    tmp_dir: dir
  } do
    {:ok, node} = start(dir)
    history(node)
    assert [%{kind: :lien_add}] = Node.proposals_for(node, pub(30))
    GenServer.stop(node)

    {:ok, node2} = start(dir)
    assert [%{kind: :lien_add, fields: %{lien: "g1"}}] = Node.proposals_for(node2, pub(30))
  end

  test "arquivo de propostas ilegível: o nó sobe com a lista vazia", %{tmp_dir: dir} do
    {:ok, node} = start(dir)
    history(node)
    GenServer.stop(node)
    File.write!(Path.join(dir, "proposals.bin"), "lixo")
    {:ok, node2} = start(dir)
    assert Node.proposals_for(node2, pub(30)) == []
    assert snapshot(node2).height == 5
  end

  test "queda no meio da escrita do último bloco: sobe até o bloco anterior e segue", %{
    tmp_dir: dir
  } do
    {:ok, node} = start(dir)
    history(node)
    GenServer.stop(node)
    log = Path.join(dir, "blocks.log")
    full = File.read!(log)
    File.write!(log, binary_part(full, 0, byte_size(full) - 7))

    {:ok, node2} = start(dir)
    assert snapshot(node2).height == 4
    # o bem (bloco 5) ainda não existe; refaz o registro e continua
    assert Node.assets_of(node2, addr(50)) == []
    mint(node2, 51, 1_000_000, "d")
    assert snapshot(node2).height == 5
  end

  test "bloco no disco com raiz de estado errada (soma válida) é recusado, e o nó não sobe", %{
    tmp_dir: dir
  } do
    {:ok, node} = start(dir)
    history(node)
    GenServer.stop(node)
    log = Path.join(dir, "blocks.log")
    {:ok, s, records, _} = LogFile.open(log)
    LogFile.close(s)

    # reescreve o log com o último bloco adulterado (raiz trocada), com soma de verificação nova e correta
    File.rm!(log)
    {:ok, s, [], _} = LogFile.open(log)
    {init, [last]} = Enum.split(records, -1)
    for r <- init, do: :ok = LogFile.append(s, r)

    # registro novo: 0xFF ‖ 1 ‖ [bloco, certificado]; reescrevemos o último no formato ANTIGO (só o bloco)
    <<0xFF, 1, env::binary>> = last
    {:ok, [block_bin, _cert]} = BrdcCrypto.Encoding.decode([:bytes, :bytes], env)
    {:ok, b} = Block.decode(block_bin)
    :ok = LogFile.append(s, Block.encode(%{b | state_root: :crypto.hash(:sha256, "outra")}))
    LogFile.close(s)

    Process.flag(:trap_exit, true)
    assert {:error, {:bad_block_on_disk, 5, :bad_state_root}} = start(dir)
  end

  test "corrupção no meio do log: o nó não sobe", %{tmp_dir: dir} do
    {:ok, node} = start(dir)
    history(node)
    GenServer.stop(node)
    log = Path.join(dir, "blocks.log")
    full = File.read!(log)
    pos = div(byte_size(full), 3)
    <<head::binary-size(^pos), b, rest::binary>> = full
    File.write!(log, head <> <<:erlang.bxor(b, 1)>> <> rest)
    Process.flag(:trap_exit, true)
    assert {:error, {:corrupt, _}} = start(dir)
  end

  test "o disco de outra rede é recusado", %{tmp_dir: dir} do
    {:ok, node} = start(dir)
    history(node)
    GenServer.stop(node)
    Process.flag(:trap_exit, true)
    assert {:error, :wrong_genesis} = start(dir, genesis: genesis("outra-rede"))
  end

  test "sem :data_dir tudo continua em memória (nada é gravado)", %{tmp_dir: dir} do
    {:ok, node} = start(nil)
    mint(node, 50, 1_000_000, "x")
    assert snapshot(node).height == 1
    assert File.ls!(dir) == []
  end

  test "bloco encode/decode: ida e volta preserva o hash e as transações", %{tmp_dir: dir} do
    {:ok, node} = start(dir)
    history(node)

    for h <- 1..5 do
      {:ok, b} = Node.block(node, h)
      assert {:ok, ^b} = Block.decode(Block.encode(b))
      assert Block.hash(b) == Block.hash(elem(Block.decode(Block.encode(b)), 1))
    end

    assert {:error, :malformed} = Block.decode("lixo")
    {:ok, b} = Node.block(node, 1)
    assert {:error, :malformed} = Block.decode(Block.encode(b) <> <<0>>)
    assert {:error, :malformed} = Block.decode(binary_part(Block.encode(b), 0, 30))
  end

  property "reiniciar = estado ao vivo, para qualquer sequência de transferências", %{
    tmp_dir: base
  } do
    check all(
            steps <-
              StreamData.list_of(
                {StreamData.integer(0..2), StreamData.integer(0..2),
                 StreamData.integer(1..400_000)},
                min_length: 1,
                max_length: 12
              ),
            max_runs: 15
          ) do
      dir = Path.join(base, "p#{System.unique_integer([:positive])}")
      {:ok, node} = start(dir)
      for n <- 50..52, do: mint(node, n, 5_000_000, "m#{n}")

      for {from, to, amount} <- steps, from != to do
        run(node, 50 + from, 1, Tx.transfer_payload(addr(50 + to), amount), 5_000)
      end

      before = snapshot(node)
      balances = for n <- 50..52, do: Node.account(node, addr(n))
      GenServer.stop(node)
      {:ok, node2} = start(dir)
      assert snapshot(node2) == before
      assert for(n <- 50..52, do: Node.account(node2, addr(n))) == balances
      GenServer.stop(node2)
    end
  end
end
