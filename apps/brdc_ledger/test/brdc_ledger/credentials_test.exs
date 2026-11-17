defmodule BrdcLedger.CredentialsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.{Account, Address, Ed25519, Hash}
  alias BrdcLedger.{Approvals, Credentials, Executor, Params, State, Tx}

  @chain "brdc-creds"
  @window 100

  defp seed(n), do: :crypto.hash(:sha256, "cred-seed-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  # 1-2: titulares · 10-11: emissores · 20-21: autoridades raiz · 30-32: órgão · 99: remetente avulso
  defp base do
    {:ok, p} =
      Params.new(
        chain_id: @chain,
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2,
        min_window: 1
      )

    State.new(p)
  end

  defp at(s, t), do: %{s | time: t}
  defp organ, do: [pub(30), pub(31), pub(32)]
  defp ap(doc, ns), do: for(n <- ns, do: Approvals.approval(doc, seed(n)))
  defp ok!({:ok, s}), do: s

  defp tx(s, n, kind, payload, fee) do
    t = %Tx{
      chain_id: @chain,
      kind: kind,
      nonce: State.account(s, addr(n)).nonce,
      fee: 0,
      sender_pub: Account.from_seed(seed(n)).public_key,
      payload: payload
    }

    Tx.sign(%{t | fee: fee || Executor.min_fee(s.params, t)}, seed(n))
  end

  defp run(s, n, kind, payload, fee \\ nil) do
    case Executor.apply_tx(s, tx(s, n, kind, payload, fee)) do
      {:ok, s2, _} -> {:ok, s2}
      err -> err
    end
  end

  defp fund(s, n, amount) do
    ref = "f-#{n}-#{s.minted}"
    d = Tx.issuance_doc(:mint, @chain, addr(n), amount, ref)

    pl =
      Tx.issuance_payload(addr(n), amount, ref, for(i <- [10, 11], do: Tx.approval(d, seed(i))))

    ok!(run(s, 99, 2, pl))
  end

  defp make_type(s, id, opts \\ []) do
    spec = %{
      id: id,
      organ: organ(),
      threshold: 2,
      contest: Keyword.get(opts, :contest, @window),
      validity: Keyword.get(opts, :validity, 0),
      privacy: Keyword.get(opts, :privacy, 0),
      ref_type: Keyword.get(opts, :ref_type, ""),
      revokes: Keyword.get(opts, :revokes, 0)
    }

    signers = Keyword.get(opts, :signers, [20, 21])
    d = Credentials.type_doc(@chain, spec)
    run(s, 99, 14, Credentials.type_payload(spec, ap(d, signers)))
  end

  defp issue(s, type, id, subject_n, data, opts \\ []) do
    ref = Keyword.get(opts, :ref, "")
    signers = Keyword.get(opts, :signers, [30, 31])
    d = Credentials.issue_doc(@chain, type, id, addr(subject_n), data, ref)

    run(
      s,
      99,
      15,
      Credentials.issue_payload(type, id, addr(subject_n), data, ref, ap(d, signers))
    )
  end

  defp commitment(text), do: Hash.tagged("brdc/test/commitment", text)
  defp contest(s, n, id), do: run(s, n, 16, Credentials.id_payload(id))
  defp activate(s, id), do: run(s, 99, 18, Credentials.id_payload(id))

  defp veto(s, id, signers \\ [30, 31]) do
    d = Credentials.veto_doc(@chain, id, s.credentials[id].issued_at)
    run(s, 99, 17, Credentials.veto_payload(id, ap(d, signers)))
  end

  defp revoke(s, id, reason \\ "erro", signers \\ [30, 31]) do
    d = Credentials.revoke_doc(@chain, id, reason)
    run(s, 99, 19, Credentials.revoke_payload(id, reason, ap(d, signers)))
  end

  defp world do
    s = base() |> fund(99, 5_000_000)
    s = ok!(make_type(s, "cnh", validity: 1_000))
    s = ok!(make_type(s, "casamento", privacy: 1))
    ok!(make_type(s, "divorcio", privacy: 1, ref_type: "casamento", revokes: 1))
  end

  describe "tipos" do
    test "autoridades raiz criam o tipo; ele guarda órgão, janela, validade e privacidade" do
      s = world()
      assert %{contest_window: @window, validity: 1_000, privacy: :public} = s.cred_types["cnh"]
      assert s.cred_types["casamento"].privacy == :private
      assert %{ref_type: "casamento", revokes_ref: true} = s.cred_types["divorcio"]
    end

    test "recusas: aprovações, duplicado, janela fora do limite, privacidade, referência inexistente, id, sem autoridade" do
      s = fund(base(), 99, 1_000_000)
      assert {:error, :not_enough_approvals} = make_type(s, "x", signers: [20])
      assert {:error, :not_enough_approvals} = make_type(s, "x", signers: [30, 31])
      assert {:error, :bad_type} = make_type(s, "x", contest: 0)
      assert {:error, :bad_type} = make_type(s, "x", contest: 99_999_999_999)
      assert {:error, :bad_type} = make_type(s, "x", privacy: 2)
      assert {:error, :bad_type} = make_type(s, "x", ref_type: "nao-existe", revokes: 1)
      assert {:error, :bad_type} = make_type(s, "x", revokes: 1)
      assert {:error, :bad_id} = make_type(s, "")
      s2 = ok!(make_type(s, "x"))
      assert {:error, :type_exists} = make_type(s2, "x")

      {:ok, p} = Params.new(chain_id: @chain, issuers: [pub(10)], threshold: 1)
      s0 = p |> State.new() |> fund(99, 1_000_000)
      assert {:error, :no_authority} = make_type(s0, "x")
    end
  end

  describe "emissão, janela e validade" do
    test "nasce pendente, ativa só depois da janela e expira pela validade" do
      s = at(world(), 1_000)
      s = ok!(issue(s, "cnh", "cnh-1", 1, "categoria=B;registro=123"))
      c = s.credentials["cnh-1"]
      assert c.status == :pending and c.active_at == 1_100 and c.expires_at == 2_000
      refute State.credential_valid?(s, "cnh-1", 1_050)

      assert {:error, :window_open} = activate(at(s, 1_099), "cnh-1")
      s = ok!(activate(at(s, 1_100), "cnh-1"))
      assert s.credentials["cnh-1"].status == :active
      assert State.credential_valid?(s, "cnh-1", 1_500)
      assert State.credential_valid?(s, "cnh-1", 1_999)
      refute State.credential_valid?(s, "cnh-1", 2_000)
      refute State.credential_valid?(s, "nao-existe", 1_500)
    end

    test "tipo sem validade nunca expira" do
      s = at(world(), 10)
      s = ok!(issue(s, "casamento", "cas-1", 1, commitment("a|b")))
      s = ok!(activate(at(s, 200), "cas-1"))
      assert State.credential_valid?(s, "cas-1", 99_999_999_999)
    end

    test "público até 512 bytes; privado exatamente 32 (compromisso)" do
      s = world()
      assert {:error, :bad_data} = issue(s, "cnh", "c", 1, String.duplicate("x", 513))
      assert {:ok, _} = issue(s, "cnh", "c", 1, String.duplicate("x", 512))
      assert {:error, :bad_data} = issue(s, "casamento", "c", 1, "curto")
      assert {:error, :bad_data} = issue(s, "casamento", "c", 1, String.duplicate("x", 33))
      assert {:ok, _} = issue(s, "casamento", "c", 1, commitment("x"))
    end

    test "o órgão precisa aprovar (M-de-N), o tipo existir, o id ser único" do
      s = world()
      assert {:error, :not_enough_approvals} = issue(s, "cnh", "c", 1, "d", signers: [30])
      assert {:error, :not_enough_approvals} = issue(s, "cnh", "c", 1, "d", signers: [20, 21])
      assert {:error, :no_type} = issue(s, "outro", "c", 1, "d")
      assert {:error, :bad_id} = issue(s, "cnh", String.duplicate("a", 65), 1, "d")
      s2 = ok!(issue(s, "cnh", "c", 1, "d"))
      assert {:error, :credential_exists} = issue(s2, "cnh", "c", 2, "d")
    end

    test "a aprovação vale só para aquele titular e aqueles dados" do
      s = world()
      d = Credentials.issue_doc(@chain, "cnh", "c", addr(1), "dados", "")
      forged = Credentials.issue_payload("cnh", "c", addr(2), "dados", "", ap(d, [30, 31]))
      assert {:error, :not_enough_approvals} = run(s, 99, 15, forged)
      forged2 = Credentials.issue_payload("cnh", "c", addr(1), "outros", "", ap(d, [30, 31]))
      assert {:error, :not_enough_approvals} = run(s, 99, 15, forged2)
    end
  end

  describe "contestação, veto e revogação" do
    setup do
      s = at(world(), 50)
      {:ok, s: ok!(issue(s, "cnh", "cnh-1", 1, "dados"))}
    end

    test "o titular contesta dentro da janela; depois não ativa; o id fica queimado", %{s: s} do
      s = ok!(contest(at(s, 100), 1, "cnh-1"))
      assert s.credentials["cnh-1"].status == :contested
      assert {:error, :bad_status} = activate(at(s, 500), "cnh-1")
      assert {:error, :credential_exists} = issue(s, "cnh", "cnh-1", 1, "dados")
    end

    test "só o titular contesta, só dentro da janela", %{s: s} do
      assert {:error, :not_subject} = contest(s, 2, "cnh-1")
      assert {:error, :window_closed} = contest(at(s, 150), 1, "cnh-1")
      assert {:error, :no_credential} = contest(s, 1, "x")
    end

    test "o órgão veta dentro da janela (M-de-N); depois do prazo não", %{s: s} do
      assert {:error, :not_enough_approvals} = veto(s, "cnh-1", [30])
      s2 = ok!(veto(s, "cnh-1"))
      assert s2.credentials["cnh-1"].status == :vetoed
      assert {:error, :window_closed} = veto(at(s, 150), "cnh-1")
    end

    test "revogação: pendente ou ativa, M-de-N, definitiva", %{s: s} do
      assert {:error, :not_enough_approvals} = revoke(s, "cnh-1", "erro", [30])
      s2 = ok!(revoke(s, "cnh-1"))
      assert s2.credentials["cnh-1"].status == :revoked
      assert {:error, :bad_status} = revoke(s2, "cnh-1")

      s3 = ok!(activate(at(s, 200), "cnh-1"))
      s3 = ok!(revoke(s3, "cnh-1", "fraude"))
      refute State.credential_valid?(s3, "cnh-1", 300)
    end

    test "a aprovação de revogação é amarrada à credencial e ao motivo", %{s: s} do
      d = Credentials.revoke_doc(@chain, "cnh-1", "erro")
      forged = Credentials.revoke_payload("cnh-1", "outro motivo", ap(d, [30, 31]))
      assert {:error, :not_enough_approvals} = run(s, 99, 19, forged)
    end
  end

  describe "casamento e divórcio" do
    defp married(s) do
      s = ok!(issue(s, "casamento", "cas-a", 1, commitment("a+b")))
      s = ok!(issue(s, "casamento", "cas-b", 2, commitment("a+b")))
      s = at(s, s.time + 200)
      s |> then(&ok!(activate(&1, "cas-a"))) |> then(&ok!(activate(&1, "cas-b")))
    end

    test "uma credencial por cônjuge; o divórcio de um revoga só o casamento dele" do
      s = married(at(world(), 10))

      assert State.credential_valid?(s, "cas-a", s.time) and
               State.credential_valid?(s, "cas-b", s.time)

      s = ok!(issue(s, "divorcio", "div-a", 1, commitment("a-b"), ref: "cas-a"))
      assert State.credential_valid?(s, "cas-a", s.time)
      s = ok!(activate(at(s, s.time + 200), "div-a"))

      assert s.credentials["cas-a"].status == :revoked
      assert s.credentials["cas-b"].status == :active
      assert State.credential_valid?(s, "div-a", s.time)
    end

    test "o divórcio exige referência ao casamento ATIVO do MESMO titular" do
      s = at(world(), 10)
      s = ok!(issue(s, "casamento", "cas-a", 1, commitment("x")))
      # casamento ainda pendente
      assert {:error, :bad_ref} = issue(s, "divorcio", "div", 1, commitment("y"), ref: "cas-a")
      s = ok!(activate(at(s, 500), "cas-a"))
      assert {:error, :bad_ref} = issue(s, "divorcio", "div", 2, commitment("y"), ref: "cas-a")
      assert {:error, :bad_ref} = issue(s, "divorcio", "div", 1, commitment("y"), ref: "")

      assert {:error, :bad_ref} =
               issue(s, "divorcio", "div", 1, commitment("y"), ref: "inexistente")

      assert {:ok, _} = issue(s, "divorcio", "div", 1, commitment("y"), ref: "cas-a")
    end

    test "tipo sem referência não aceita referência" do
      s = at(world(), 10)
      assert {:error, :bad_ref} = issue(s, "cnh", "c", 1, "d", ref: "algo")
    end

    test "divórcio vetado ou contestado não revoga o casamento" do
      s = married(at(world(), 10))
      s = ok!(issue(s, "divorcio", "div-a", 1, commitment("z"), ref: "cas-a"))
      s = ok!(contest(s, 1, "div-a"))
      assert s.credentials["cas-a"].status == :active
      assert {:error, :bad_status} = activate(at(s, s.time + 500), "div-a")
    end

    test "casamento já revogado: ativar o divórcio não quebra" do
      s = married(at(world(), 10))
      s = ok!(issue(s, "divorcio", "div-a", 1, commitment("z"), ref: "cas-a"))
      s = ok!(revoke(s, "cas-a"))
      s = ok!(activate(at(s, s.time + 500), "div-a"))

      assert s.credentials["cas-a"].status == :revoked and
               s.credentials["div-a"].status == :active
    end
  end

  describe "taxas (ADR-0014/0019)" do
    test "emissão e revogação 0,01; tipo 0,05; o resto sem mínimo" do
      p = world().params

      mk = fn k ->
        %Tx{chain_id: @chain, kind: k, nonce: 0, fee: 0, sender_pub: pub(1), payload: ""}
      end

      fees = Enum.map(14..19, &Executor.min_fee(p, mk.(&1)))
      assert fees == [50_000, 10_000, 0, 0, 0, 10_000]
    end

    test "taxa abaixo do mínimo é recusada" do
      s = world()
      d = Credentials.issue_doc(@chain, "cnh", "c", addr(1), "d", "")
      pl = Credentials.issue_payload("cnh", "c", addr(1), "d", "", ap(d, [30, 31]))
      assert {:error, :fee_too_low} = run(s, 99, 15, pl, 9_999)
    end
  end

  test "carga malformada é recusada sem exceção" do
    s = world()
    for kind <- 14..19, do: assert({:error, _} = run(s, 1, kind, "lixo", 100_000))
  end

  describe "propriedade" do
    defp op_gen do
      one_of([
        tuple({constant(:issue), integer(1..2), member_of(["cas-1", "cas-2"])}),
        tuple(
          {constant(:divorce), integer(1..2), member_of(["cas-1", "cas-2"]),
           member_of(["div-1", "div-2"])}
        ),
        tuple({constant(:activate), member_of(["cas-1", "cas-2", "div-1", "div-2"])}),
        tuple(
          {constant(:contest), integer(1..2), member_of(["cas-1", "cas-2", "div-1", "div-2"])}
        ),
        tuple({constant(:veto), member_of(["cas-1", "cas-2", "div-1", "div-2"])}),
        tuple({constant(:revoke), member_of(["cas-1", "cas-2", "div-1", "div-2"])}),
        tuple({constant(:advance), integer(1..150)})
      ])
    end

    defp step(s, {:issue, n, id}), do: issue(s, "casamento", id, n, commitment(id))

    defp step(s, {:divorce, n, ref, id}),
      do: issue(s, "divorcio", id, n, commitment(id), ref: ref)

    defp step(s, {:activate, id}), do: activate(s, id)
    defp step(s, {:contest, n, id}), do: contest(s, n, id)

    defp step(s, {:veto, id}),
      do: if(s.credentials[id], do: veto(s, id), else: {:error, :no_credential})

    defp step(s, {:revoke, id}), do: revoke(s, id)
    defp step(s, {:advance, secs}), do: {:ok, at(s, s.time + secs)}

    property "em qualquer sequência: ids nunca se repetem, só ativo é válido, divórcio ativo sempre deixa o casamento revogado" do
      check all(ops <- list_of(op_gen(), max_length: 40), max_runs: 80) do
        s0 = at(world(), 10)

        s =
          Enum.reduce(ops, s0, fn op, s ->
            case step(s, op) do
              {:ok, s2} -> s2
              {:error, _} -> s
            end
          end)

        for {id, c} <- s.credentials do
          assert State.credential_valid?(s, id, s.time) ==
                   (c.status == :active and (c.expires_at == 0 or s.time < c.expires_at))

          assert c.status in [:pending, :active, :contested, :vetoed, :revoked]

          if c.type == "divorcio" and c.status == :active do
            assert s.credentials[c.ref].status == :revoked
          end
        end
      end
    end
  end
end
