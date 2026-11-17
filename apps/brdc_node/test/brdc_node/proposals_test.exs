defmodule BrdcNode.ProposalsTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Address, Ed25519, Hash}
  alias BrdcLedger.{Approvals, Credentials, Tx}
  alias BrdcNode.{Genesis, Node, Proposals}

  defp seed(n), do: :crypto.hash(:sha256, "prop-node-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  # 1 validador · 10-11 emissores · 20-21 autoridades · 30-32 órgão · 50 titular · 99 remetente
  defp genesis do
    {:ok, g} =
      Genesis.new(
        chain_id: "prop-test",
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2,
        min_window: 1
      )

    g
  end

  defp signed(node, n, kind, payload, fee) do
    nonce = Node.account(node, addr(n), pending: true).nonce

    Tx.sign(
      %Tx{
        chain_id: "prop-test",
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
    {:ok, _} = Node.produce(node) |> then(&{:ok, &1})
  end

  # nó com um tipo "cnh" (público) e um "casamento" (privado), órgão 30-32 com 2 de 3
  defp world(clock \\ fn -> 1_000 end) do
    {:ok, node} =
      Node.start_link(
        genesis: genesis(),
        seed: seed(1),
        block_interval_ms: :manual,
        clock: clock
      )

    d = Tx.issuance_doc(:mint, "prop-test", addr(99), 5_000_000, "dep")

    run(
      node,
      99,
      2,
      Tx.issuance_payload(
        addr(99),
        5_000_000,
        "dep",
        for(i <- [10, 11], do: Tx.approval(d, seed(i)))
      )
    )

    for {id, privacy} <- [{"cnh", 0}, {"casamento", 1}] do
      spec = %{
        id: id,
        organ: [pub(30), pub(31), pub(32)],
        threshold: 2,
        contest: 60,
        validity: 0,
        privacy: privacy,
        ref_type: "",
        revokes: 0
      }

      doc = Credentials.type_doc("prop-test", spec)
      ap = for i <- [20, 21], do: Approvals.approval(doc, seed(i))
      run(node, 99, 14, Credentials.type_payload(spec, ap), 50_000)
    end

    node
  end

  defp fields(over \\ %{}),
    do:
      Map.merge(
        %{type: "cnh", id: "cnh-1", subject: addr(50), data: "categoria=B", ref: ""},
        over
      )

  defp approval(n, node_fields) do
    doc =
      Credentials.issue_doc(
        "prop-test",
        node_fields.type,
        node_fields.id,
        node_fields.subject,
        node_fields.data,
        node_fields.ref
      )

    Approvals.approval(doc, seed(n))
  end

  test "o id é o hash dos campos; o documento é recalculado, nunca recebido" do
    f = fields()
    assert Proposals.id_of(f) == Proposals.id_of(fields())
    refute Proposals.id_of(f) == Proposals.id_of(fields(%{data: "categoria=A"}))
    assert byte_size(Proposals.id_of(f)) == 32
    refute Proposals.id_of(f) == Hash.tagged("brdc/proposal/outro", "x")
  end

  test "propor: só campos válidos; a mesma proposta é idempotente; outra para o mesmo id é recusada" do
    node = world()
    assert {:ok, id} = Node.propose(node, fields())
    assert {:ok, ^id} = Node.propose(node, fields())
    assert {:error, :proposal_exists} = Node.propose(node, fields(%{data: "categoria=A"}))
    assert {:error, :no_type} = Node.propose(node, fields(%{type: "x", id: "outra"}))

    assert {:error, :bad_data} =
             Node.propose(node, fields(%{type: "casamento", id: "c1", data: "curto"}))

    assert {:error, :bad_id} = Node.propose(node, fields(%{id: ""}))

    assert {:ok, _} =
             Node.propose(
               node,
               fields(%{type: "casamento", id: "c1", data: :crypto.hash(:sha256, "c")})
             )
  end

  test "aprovar: só membros do órgão, só sobre o documento recalculado; duplicada não conta" do
    node = world()
    f = fields()
    {:ok, id} = Node.propose(node, f)

    assert {:ok, 1} = Node.approve(node, id, approval(30, f))
    assert {:ok, 1} = Node.approve(node, id, approval(30, f))
    assert {:ok, 2} = Node.approve(node, id, approval(31, f))

    # estranho ao órgão; autoridade raiz não é do órgão; aprovação de outro documento; proposta inexistente
    assert {:error, :bad_approval} = Node.approve(node, id, approval(99, f))
    assert {:error, :bad_approval} = Node.approve(node, id, approval(20, f))

    assert {:error, :bad_approval} =
             Node.approve(node, id, approval(32, fields(%{data: "categoria=A"})))

    assert {:error, :no_proposal} = Node.approve(node, <<0::256>>, approval(32, f))
    assert {:error, :bad_approval} = Node.approve(node, id, <<0::768>>)
  end

  test "listar: só as propostas dos órgãos de que a chave faz parte, com aprovações e limite" do
    node = world()
    f = fields()
    {:ok, id} = Node.propose(node, f)
    {:ok, _} = Node.approve(node, id, approval(30, f))

    assert [%{id: ^id, threshold: 2, approvals: [ap]}] = Node.proposals_for(node, pub(31))
    assert binary_part(ap, 0, 32) == pub(30)
    assert Node.proposals_for(node, pub(99)) == []
    assert Node.proposals_for(node, pub(20)) == []
  end

  test "tipos de quem é do órgão" do
    node = world()
    assert [%{id: "casamento"}, %{id: "cnh"}] = Node.types_for(node, pub(30))
    assert Node.types_for(node, pub(50)) == []
  end

  test "ciclo completo: propor, aprovar (2 de 3), enviar a transação, credencial emitida, proposta some" do
    node = world()
    f = fields()
    {:ok, id} = Node.propose(node, f)
    {:ok, _} = Node.approve(node, id, approval(30, f))
    {:ok, 2} = Node.approve(node, id, approval(32, f))

    [%{approvals: approvals}] = Node.proposals_for(node, pub(30))
    payload = Credentials.issue_payload(f.type, f.id, f.subject, f.data, f.ref, approvals)
    run(node, 99, 15, payload, 10_000)

    assert [%{id: "cnh-1", type: "cnh", status: :pending, data: "categoria=B"}] =
             Node.credentials_of(node, addr(50))

    assert Node.credentials_of(node, addr(99)) == []
    # a credencial já existe: a proposta sai da lista, e propor de novo é recusado
    assert Node.proposals_for(node, pub(30)) == []
    assert {:error, :credential_exists} = Node.propose(node, f)
  end

  test "com aprovações a menos, a transação é recusada pelo nó (o limite é do ledger)" do
    node = world()
    f = fields()
    {:ok, id} = Node.propose(node, f)
    {:ok, 1} = Node.approve(node, id, approval(30, f))
    [%{approvals: approvals}] = Node.proposals_for(node, pub(30))
    payload = Credentials.issue_payload(f.type, f.id, f.subject, f.data, f.ref, approvals)

    assert {:error, :not_enough_approvals} =
             Node.submit(node, Tx.encode(signed(node, 99, 15, payload, 10_000)))
  end

  test "o armazém tem teto de propostas" do
    node = world()

    results =
      for i <- 1..205 do
        Node.propose(node, fields(%{id: "c#{i}"}))
      end

    assert Enum.count(results, &match?({:ok, _}, &1)) == 200
    assert Enum.count(results, &(&1 == {:error, :too_many_proposals})) == 5
  end

  test "sem blocos novos, a janela de contestação vence pelo relógio (a conferência usa o horário do próximo bloco)" do
    {:ok, clock} = Agent.start_link(fn -> 1_000 end)
    node = world(fn -> Agent.get(clock, & &1) end)
    f = fields()
    {:ok, id} = Node.propose(node, f)
    {:ok, _} = Node.approve(node, id, approval(30, f))
    {:ok, _} = Node.approve(node, id, approval(31, f))
    [%{approvals: approvals}] = Node.proposals_for(node, pub(30))

    run(
      node,
      99,
      15,
      Credentials.issue_payload(f.type, f.id, f.subject, f.data, f.ref, approvals),
      10_000
    )

    activate = fn ->
      Tx.encode(signed(node, 50, 18, BrdcCrypto.Encoding.encode([:string], [f.id]), 0))
    end

    assert {:error, :window_open} = Node.submit(node, activate.())

    # 100 s depois, SEM nenhum bloco novo: a janela de 60 s já passou
    Agent.update(clock, fn _ -> 1_100 end)
    assert {:ok, _} = Node.submit(node, activate.())
    Node.produce(node)
    assert [%{status: :active}] = Node.credentials_of(node, addr(50))
  end

  # emite cnh-1 (público, janela de 60 s) e devolve o nó
  defp with_credential(clock \\ fn -> 1_000 end) do
    node = world(clock)
    f = fields()
    {:ok, id} = Node.propose(node, f)
    for i <- [30, 31], do: Node.approve(node, id, approval(i, f))
    [%{approvals: ap}] = Node.proposals_for(node, pub(30))

    run(
      node,
      99,
      15,
      Credentials.issue_payload(f.type, f.id, f.subject, f.data, f.ref, ap),
      10_000
    )

    node
  end

  defp sign_doc(doc, signers), do: for(i <- signers, do: Approvals.approval(doc, seed(i)))
  defp veto_doc, do: Credentials.veto_doc("prop-test", "cnh-1", 1_000)

  test "veto de credencial por proposta: só com a credencial pendente e dentro da janela" do
    node = with_credential()
    assert [%{id: "cnh-1", status: :pending}] = Node.organ_credentials(node, pub(30))
    assert Node.organ_credentials(node, pub(50)) == []

    assert {:ok, id} = Node.propose(node, :cred_veto, %{id: "cnh-1"})
    assert {:error, :no_credential} = Node.propose(node, :cred_veto, %{id: "x"})
    [a, b] = sign_doc(veto_doc(), [30, 32])
    assert {:ok, 1} = Node.approve(node, id, a)
    assert {:ok, 2} = Node.approve(node, id, b)
    assert {:error, :bad_approval} = Node.approve(node, id, hd(sign_doc(veto_doc(), [50])))

    [%{approvals: ap}] = Node.proposals_for(node, pub(31))
    run(node, 99, 17, Credentials.veto_payload("cnh-1", ap))
    assert [%{status: :vetoed}] = Node.credentials_of(node, addr(50))
    # não está mais pendente: a proposta caducou
    assert Node.proposals_for(node, pub(31)) == []
  end

  test "proposta de veto de credencial caduca quando a janela de contestação passa" do
    {:ok, clock} = Agent.start_link(fn -> 1_000 end)
    node = with_credential(fn -> Agent.get(clock, & &1) end)
    {:ok, _} = Node.propose(node, :cred_veto, %{id: "cnh-1"})
    Agent.update(clock, fn _ -> 1_100 end)
    assert Node.proposals_for(node, pub(30)) == []
    assert {:error, :window_closed} = Node.propose(node, :cred_veto, %{id: "cnh-1"})
  end

  test "revogação de credencial ativa por proposta; o motivo é parte do documento" do
    {:ok, clock} = Agent.start_link(fn -> 1_000 end)
    node = with_credential(fn -> Agent.get(clock, & &1) end)
    Agent.update(clock, fn _ -> 1_100 end)
    run(node, 50, 18, BrdcCrypto.Encoding.encode([:string], ["cnh-1"]))
    assert [%{status: :active}] = Node.credentials_of(node, addr(50))

    assert {:error, :bad_id} = Node.propose(node, :cred_revoke, %{id: "cnh-1", reason: ""})
    f = %{id: "cnh-1", reason: "fraude"}
    assert {:ok, id} = Node.propose(node, :cred_revoke, f)
    doc = Credentials.revoke_doc("prop-test", "cnh-1", "fraude")
    for i <- [30, 31], do: Node.approve(node, id, hd(sign_doc(doc, [i])))
    # aprovação para outro motivo não vale
    other = Credentials.revoke_doc("prop-test", "cnh-1", "outro")
    assert {:error, :bad_approval} = Node.approve(node, id, hd(sign_doc(other, [32])))

    [%{approvals: ap}] = Node.proposals_for(node, pub(32))
    run(node, 99, 19, Credentials.revoke_payload("cnh-1", "fraude", ap), 10_000)
    assert [%{status: :revoked}] = Node.credentials_of(node, addr(50))
    assert Node.proposals_for(node, pub(32)) == []
  end
end
