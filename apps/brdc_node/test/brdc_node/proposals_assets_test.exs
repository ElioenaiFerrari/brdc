defmodule BrdcNode.ProposalsAssetsTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Approvals, Assets, Tx}
  alias BrdcNode.{Genesis, Node, Proposals}

  defp seed(n), do: :crypto.hash(:sha256, "prop-assets-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  # 1 validador · 10-11 emissores · 20-21 autoridades · 30-32 órgão (2 de 3) · 50 dono · 51 comprador · 99 remetente
  defp world(clock \\ fn -> 1_000 end) do
    {:ok, g} =
      Genesis.new(
        chain_id: "prop-assets",
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2,
        min_window: 1
      )

    {:ok, node} =
      Node.start_link(
        genesis: g,
        seed: seed(1),
        block_interval_ms: :manual,
        clock: clock
      )

    for n <- [99, 50, 51] do
      d = Tx.issuance_doc(:mint, "prop-assets", addr(n), 10_000_000, "dep-#{n}")

      run(
        node,
        99,
        2,
        Tx.issuance_payload(
          addr(n),
          10_000_000,
          "dep-#{n}",
          for(i <- [10, 11], do: Tx.approval(d, seed(i)))
        )
      )
    end

    organ = [pub(30), pub(31), pub(32)]
    doc = Assets.class_doc("prop-assets", "imovel", organ, 2, 60)
    ap = for i <- [20, 21], do: Approvals.approval(doc, seed(i))
    run(node, 99, 5, Assets.class_payload("imovel", organ, 2, 60, ap), 50_000)
    node
  end

  defp signed(node, n, kind, payload, fee) do
    nonce = Node.account(node, addr(n), pending: true).nonce

    Tx.sign(
      %Tx{
        chain_id: "prop-assets",
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

  defp doc_of(node, kind, f) do
    # o documento é o do estado do ledger: pede ao próprio módulo
    {:ok, d} = Proposals.doc(:sys.get_state(node).state, kind, f)
    d
  end

  defp sign(node, kind, f, signers),
    do: for(i <- signers, do: Approvals.approval(doc_of(node, kind, f), seed(i)))

  defp register_fields,
    do: %{class: "imovel", asset: "casa-1", owner: addr(50), meta: "Rua A, 10"}

  # registra casa-1 diretamente (com as aprovações do órgão), para testar veto e gravame
  defp registered(clock \\ fn -> 1_000 end) do
    node = world(clock)
    f = register_fields()
    ap = sign(node, :asset_register, f, [30, 31])
    run(node, 99, 6, Assets.register_payload(f.class, f.asset, f.owner, f.meta, ap), 50_000)
    node
  end

  test "registro: propor, assinar (2 de 3), enviar; o bem passa a existir e a proposta some" do
    node = world()
    f = register_fields()
    assert {:ok, id} = Node.propose(node, :asset_register, f)
    assert {:ok, ^id} = Node.propose(node, :asset_register, f)
    assert {:ok, 1} = Node.approve(node, id, hd(sign(node, :asset_register, f, [30])))

    assert {:error, :bad_approval} =
             Node.approve(node, id, hd(sign(node, :asset_register, f, [20])))

    assert {:ok, 2} = Node.approve(node, id, hd(sign(node, :asset_register, f, [32])))

    assert [%{kind: :asset_register, approvals: ap, threshold: 2}] =
             Node.proposals_for(node, pub(31))

    run(node, 99, 6, Assets.register_payload(f.class, f.asset, f.owner, f.meta, ap), 50_000)

    assert [%{id: "casa-1", role: "owner", lien_ids: []}] = Node.assets_of(node, addr(50))
    assert Node.proposals_for(node, pub(31)) == []
    assert {:error, :asset_exists} = Node.propose(node, :asset_register, f)
  end

  test "registro: classe inexistente, id inválido e proposta concorrente para o mesmo bem" do
    node = world()

    assert {:error, :no_class} =
             Node.propose(node, :asset_register, %{register_fields() | class: "x"})

    assert {:error, :bad_id} =
             Node.propose(node, :asset_register, %{register_fields() | asset: ""})

    assert {:ok, _} = Node.propose(node, :asset_register, register_fields())

    assert {:error, :proposal_exists} =
             Node.propose(node, :asset_register, %{register_fields() | meta: "outra"})
  end

  test "classes e bens do órgão: só quem é do órgão da classe os vê" do
    node = registered()
    assert [%{id: "imovel", threshold: 2, veto_window: 60}] = Node.classes_for(node, pub(30))
    assert Node.classes_for(node, pub(50)) == []
    assert [%{id: "casa-1", role: "class"}] = Node.organ_assets(node, pub(31))
    assert Node.organ_assets(node, pub(50)) == []
  end

  test "veto: só com negociação aceita; o documento amarra comprador, preço e prazo do estado" do
    node = registered()
    assert {:error, :no_deal} = Node.propose(node, :asset_veto, %{asset: "casa-1"})

    run(node, 50, 7, Assets.offer_payload("casa-1", addr(51), 3_000_000), 20_000)
    assert {:error, :bad_status} = Node.propose(node, :asset_veto, %{asset: "casa-1"})
    run(node, 51, 8, Assets.asset_payload("casa-1"), 20_000)

    f = %{asset: "casa-1"}
    assert {:ok, id} = Node.propose(node, :asset_veto, f)
    for i <- [30, 31], do: Node.approve(node, id, hd(sign(node, :asset_veto, f, [i])))
    [%{approvals: ap}] = Node.proposals_for(node, pub(32))

    before = Node.account(node, addr(51)).balance
    run(node, 99, 10, Assets.veto_payload("casa-1", ap))
    assert Node.account(node, addr(51)).balance == before + 3_000_000
    assert [%{deal: nil, rev: 1}] = Node.assets_of(node, addr(50))
    # a negociação acabou: a proposta caducou
    assert Node.proposals_for(node, pub(30)) == []
  end

  test "gravame: adicionar e remover por proposta; a proposta de adicionar caduca ao ser executada" do
    node = registered()
    add = %{asset: "casa-1", lien: "hipoteca-1", ref: "contrato 42"}
    assert {:ok, id} = Node.propose(node, :lien_add, add)
    assert {:error, :bad_id} = Node.propose(node, :lien_add, %{add | lien: ""})
    for i <- [30, 31], do: Node.approve(node, id, hd(sign(node, :lien_add, add, [i])))
    [%{approvals: ap}] = Node.proposals_for(node, pub(30))
    run(node, 99, 12, Assets.lien_add_payload("casa-1", "hipoteca-1", "contrato 42", ap))

    assert [%{lien_ids: ["hipoteca-1"], rev: 1}] = Node.assets_of(node, addr(50))
    assert Node.proposals_for(node, pub(30)) == []
    assert {:error, :lien_exists} = Node.propose(node, :lien_add, add)

    rm = %{asset: "casa-1", lien: "hipoteca-1"}
    assert {:error, :no_lien} = Node.propose(node, :lien_remove, %{rm | lien: "outro"})
    assert {:ok, rid} = Node.propose(node, :lien_remove, rm)
    for i <- [31, 32], do: Node.approve(node, rid, hd(sign(node, :lien_remove, rm, [i])))
    [%{approvals: rap}] = Node.proposals_for(node, pub(30))
    run(node, 99, 13, Assets.lien_remove_payload("casa-1", "hipoteca-1", rap))
    assert [%{lien_ids: [], rev: 2}] = Node.assets_of(node, addr(50))
  end

  test "a aprovação de uma revisão antiga não vale: a revisão do bem muda o documento" do
    node = registered()
    add = %{asset: "casa-1", lien: "g1", ref: "a"}
    {:ok, id} = Node.propose(node, :lien_add, add)
    old = hd(sign(node, :lien_add, add, [30]))
    {:ok, 1} = Node.approve(node, id, old)

    # outro gravame passa antes (sobe a revisão): a proposta g1 ainda vale, mas a aprovação antiga não
    other = %{asset: "casa-1", lien: "g2", ref: "b"}
    {:ok, oid} = Node.propose(node, :lien_add, other)
    for i <- [31, 32], do: Node.approve(node, oid, hd(sign(node, :lien_add, other, [i])))
    [%{approvals: oap}] = Enum.filter(Node.proposals_for(node, pub(31)), &(&1.id == oid))
    # as 2 aprovações já estão; a proposta anterior (g1) tem só 1 de revisão 0
    run(node, 99, 12, Assets.lien_add_payload("casa-1", "g2", "b", oap))

    [still] = Node.proposals_for(node, pub(30))
    assert still.id == id
    # a aprovação antiga (rev 0) não é aceita de novo agora que o bem está na revisão 1
    assert {:error, :bad_approval} = Node.approve(node, id, old)
  end

  test "campos de tipo desconhecido ou malformados são recusados pela porta pública" do
    node = world()
    h = BrdcNode.Handler.fun(node)
    assert {:error, :bad_proposal} = h.(:proposal, <<9, 9, 9>>)
    assert {:error, :malformed} = h.(:proposal, <<1, 99, 1, 2>>)
    assert {:error, :malformed} = h.(:proposal, <<1, 2, 1, 2>>)
  end

  test "proposta de veto caduca quando a janela de veto passa (mesmo sem blocos novos)" do
    {:ok, clock} = Agent.start_link(fn -> 1_000 end)
    node = registered(fn -> Agent.get(clock, & &1) end)
    run(node, 50, 7, Assets.offer_payload("casa-1", addr(51), 3_000_000), 20_000)
    run(node, 51, 8, Assets.asset_payload("casa-1"), 20_000)

    f = %{asset: "casa-1"}
    assert {:ok, id} = Node.propose(node, :asset_veto, f)
    assert [%{id: ^id}] = Node.proposals_for(node, pub(30))

    # a janela da classe é de 60 s: 100 s depois, sem bloco algum, a proposta já não vale
    Agent.update(clock, fn _ -> 1_100 end)
    assert Node.proposals_for(node, pub(30)) == []
    assert {:error, :window_closed} = Node.propose(node, :asset_veto, f)
    assert {:error, :window_closed} = Node.approve(node, id, hd(sign(node, :asset_veto, f, [30])))
  end
end
