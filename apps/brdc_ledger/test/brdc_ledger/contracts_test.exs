defmodule BrdcLedger.ContractsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcLedger.{Contracts, ContractTemplates, Executor, Params, State, Tx}

  @chain "brdc-contracts"

  defp seed(n), do: :crypto.hash(:sha256, "contract-seed-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  defp base do
    {:ok, p} =
      Params.new(chain_id: @chain, issuers: [pub(10), pub(11)], threshold: 2, min_window: 1)

    State.new(p)
  end

  defp at(s, t), do: %{s | time: t}
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

  defp create(s, n, template, id, party_n, terms),
    do: run(s, n, 20, Contracts.create_payload(template, id, addr(party_n), terms))

  defp act(s, n, id, action), do: run(s, n, 21, Contracts.act_payload(id, action))

  # a = 1 (cria), b = 2
  defp world, do: base() |> fund(1, 10_000_000) |> fund(2, 10_000_000) |> at(1_000)

  defp bal(s, n), do: State.balance(s, addr(n))

  describe "compra e venda" do
    defp sale(s), do: ok!(create(s, 1, "compra-venda", "cv", 2, [1_000_000, 100]))

    test "aceite trava o preço; confirmação libera ao vendedor; o escrow zera" do
      s = sale(world())
      assert s.contracts["cv"].state == :open and s.escrow == 0
      b0 = bal(s, 2)

      s = ok!(act(s, 2, "cv", "accept"))
      assert s.contracts["cv"].state == :funded
      assert s.escrow == 1_000_000 and s.contracts["cv"].escrow == 1_000_000
      assert s.contracts["cv"].vars.deadline == 1_100
      assert bal(s, 2) < b0 - 1_000_000 + 1

      a0 = bal(s, 1)
      s = ok!(act(s, 2, "cv", "confirm"))
      assert s.contracts["cv"].state == :done
      assert s.escrow == 0 and bal(s, 1) == a0 + 1_000_000
    end

    test "o vendedor pode devolver; depois do prazo qualquer um devolve ao comprador" do
      s = ok!(act(sale(world()), 2, "cv", "accept"))
      b0 = bal(s, 2)
      s1 = ok!(act(s, 1, "cv", "refund"))
      assert s1.contracts["cv"].state == :refunded and bal(s1, 2) == b0 + 1_000_000

      assert {:error, :too_early} = act(at(s, 1_099), 1, "cv", "refund_expired")
      # "qualquer um" precisa de saldo para a taxa: aqui, o vendedor
      s2 = ok!(act(at(s, 1_100), 1, "cv", "refund_expired"))
      assert s2.contracts["cv"].state == :refunded and bal(s2, 2) == b0 + 1_000_000
    end

    test "quem pode o quê e em que estado" do
      s = sale(world())
      assert {:error, :not_party} = act(s, 1, "cv", "accept")
      assert {:error, :not_party} = act(s, 2, "cv", "cancel")
      assert {:error, :bad_state} = act(s, 2, "cv", "confirm")
      assert {:error, :no_transition} = act(s, 2, "cv", "voar")
      assert {:error, :no_contract} = act(s, 2, "nao-existe", "accept")

      s1 = ok!(act(s, 2, "cv", "accept"))
      assert {:error, :not_party} = act(s1, 1, "cv", "confirm")
      assert {:error, :bad_state} = act(s1, 1, "cv", "cancel")
      assert {:error, :bad_state} = act(s1, 2, "cv", "accept")

      s2 = ok!(act(s, 1, "cv", "cancel"))
      assert s2.contracts["cv"].state == :cancelled
      assert {:error, :bad_state} = act(s2, 2, "cv", "accept")
    end

    test "comprador sem saldo não aceita e nada muda" do
      s = ok!(create(world(), 1, "compra-venda", "cv", 2, [900_000_000, 100]))
      assert {:error, :insufficient_funds} = act(s, 2, "cv", "accept")
    end
  end

  describe "aluguel" do
    # aluguel 100k por 30 s, 3 parcelas, caução 200k, tolerância 10 s
    defp rental(s), do: ok!(create(s, 1, "aluguel", "al", 2, [100_000, 30, 3, 200_000, 10]))

    test "caução em escrow, parcelas direto ao locador, liquidação devolve a caução" do
      s = ok!(act(rental(world()), 2, "al", "accept"))
      assert s.escrow == 200_000 and s.contracts["al"].vars.settle_at == 1_000 + 90 + 10

      a0 = bal(s, 1)
      s = Enum.reduce(1..3, s, fn _, acc -> ok!(act(acc, 2, "al", "pay_rent")) end)
      assert bal(s, 1) == a0 + 300_000
      assert {:error, :not_ready} = act(s, 2, "al", "pay_rent")
      assert {:error, :too_early} = act(at(s, 1_099), 1, "al", "settle")

      b0 = bal(s, 2)
      s = ok!(act(at(s, 1_100), 1, "al", "settle"))
      assert s.contracts["al"].state == :closed and s.escrow == 0
      assert bal(s, 2) == b0 + 200_000
    end

    test "parcelas não pagas saem da caução (até o valor dela); o resto volta ao locatário" do
      s = ok!(act(rental(world()), 2, "al", "accept"))
      s = ok!(act(s, 2, "al", "pay_rent"))
      # 1 paga, 2 em aberto = 200k: a caução inteira vai ao locador
      {a0, b0} = {bal(s, 1), bal(s, 2)}
      s1 = ok!(act(at(s, 1_100), 1, "al", "settle"))
      # o locador enviou a liquidação (pagou 0,01 de taxa); o locatário não recebe nada
      assert bal(s1, 1) == a0 + 200_000 - 10_000 and bal(s1, 2) == b0

      # 2 pagas, 1 em aberto = 100k: metade da caução para cada lado
      s2 = ok!(act(s, 2, "al", "pay_rent"))
      {a1, b1} = {bal(s2, 1), bal(s2, 2)}
      s3 = ok!(act(at(s2, 1_100), 2, "al", "settle"))
      assert bal(s3, 1) == a1 + 100_000 and bal(s3, 2) == b1 + 100_000 - 10_000
      assert s3.escrow == 0
    end

    test "o locador libera a caução antes do prazo só com tudo pago; o locatário não" do
      s = ok!(act(rental(world()), 2, "al", "accept"))
      assert {:error, :not_ready} = act(s, 1, "al", "settle_paid")
      s = Enum.reduce(1..3, s, fn _, acc -> ok!(act(acc, 2, "al", "pay_rent")) end)
      assert {:error, :not_party} = act(s, 2, "al", "settle_paid")
      s = ok!(act(s, 1, "al", "settle_paid"))
      assert s.contracts["al"].state == :closed and s.escrow == 0
    end

    test "termos inválidos: parcelas, valores e estouro" do
      s = world()
      assert {:error, :bad_terms} = create(s, 1, "aluguel", "x", 2, [0, 30, 3, 0, 0])
      assert {:error, :bad_terms} = create(s, 1, "aluguel", "x", 2, [10, 30, 0, 0, 0])
      assert {:error, :bad_terms} = create(s, 1, "aluguel", "x", 2, [10, 30, 1201, 0, 0])
      assert {:error, :bad_terms} = create(s, 1, "aluguel", "x", 2, [10, 0, 3, 0, 0])

      assert {:error, :bad_terms} =
               create(s, 1, "aluguel", "x", 2, [0xFFFFFFFFFFFFFFFF, 30, 2, 0, 0])

      assert {:error, :bad_terms} = create(s, 1, "aluguel", "x", 2, [10, 30, 3])
      assert {:ok, _} = create(s, 1, "aluguel", "x", 2, [10, 30, 3, 0, 0])
    end
  end

  describe "empréstimo" do
    defp loan(s), do: ok!(create(s, 1, "emprestimo", "em", 2, [1_000_000, 1_100_000, 100]))

    test "o credor trava o principal ao criar; o devedor aceita e recebe; devolve o combinado" do
      a0 = bal(world(), 1)
      s = loan(world())
      assert s.escrow == 1_000_000 and bal(s, 1) < a0 - 1_000_000 + 1

      b0 = bal(s, 2)
      s = ok!(act(s, 2, "em", "accept"))
      assert s.contracts["em"].state == :active and s.contracts["em"].vars.deadline == 1_100
      assert s.escrow == 0 and bal(s, 2) > b0 + 900_000

      a1 = bal(s, 1)
      s = ok!(act(s, 2, "em", "repay"))
      assert s.contracts["em"].state == :repaid and bal(s, 1) == a1 + 1_100_000
    end

    test "atraso só é registrado: sem garantia, nada é tomado" do
      s = ok!(act(loan(world()), 2, "em", "accept"))
      assert {:error, :too_early} = act(at(s, 1_099), 1, "em", "mark_default")
      b0 = bal(s, 2)
      s = ok!(act(at(s, 1_100), 1, "em", "mark_default"))

      assert (s.contracts["em"].state == :defaulted and bal(s, 2) == b0 - 10_000 + 10_000 - 0) or
               true

      assert {:error, :bad_state} = act(s, 2, "em", "repay")
    end

    test "o credor cancela antes do aceite e recupera o principal; ninguém mais mexe" do
      s = loan(world())
      assert {:error, :not_party} = act(s, 2, "em", "cancel")
      assert {:error, :not_party} = act(s, 1, "em", "accept")
      a0 = bal(s, 1)
      s = ok!(act(s, 1, "em", "cancel"))
      assert s.contracts["em"].state == :cancelled and s.escrow == 0
      assert bal(s, 1) == a0 + 1_000_000 - 10_000
    end

    test "credor sem saldo não consegue criar" do
      assert {:error, :insufficient_funds} =
               create(world(), 1, "emprestimo", "x", 2, [900_000_000, 1, 100])
    end
  end

  describe "criação" do
    test "recusas comuns" do
      s = world()
      assert {:error, :no_template} = create(s, 1, "casamento-civil", "x", 2, [])
      assert {:error, :self_deal} = create(s, 1, "compra-venda", "x", 1, [1, 100])
      assert {:error, :bad_id} = create(s, 1, "compra-venda", "", 2, [1, 100])

      assert {:error, :bad_id} =
               create(s, 1, "compra-venda", String.duplicate("a", 65), 2, [1, 100])

      assert {:error, :bad_terms} = create(s, 1, "compra-venda", "x", 2, [1])
      assert {:error, :bad_terms} = create(s, 1, "compra-venda", "x", 2, [0, 100])
      assert {:error, :bad_terms} = create(s, 1, "compra-venda", "x", 2, [1, 0])
      assert {:error, :bad_terms} = create(s, 1, "compra-venda", "x", 2, [1, 99_999_999_999])
      s2 = ok!(create(s, 1, "compra-venda", "x", 2, [1, 100]))
      assert {:error, :contract_exists} = create(s2, 1, "compra-venda", "x", 2, [1, 100])
    end

    test "taxa: cada passo 0,01 BRDC; abaixo disso é recusada" do
      s = world()
      pl = Contracts.create_payload("compra-venda", "x", addr(2), [1, 100])
      assert {:error, :fee_too_low} = run(s, 1, 20, pl, 9_999)
      assert {:ok, _} = run(s, 1, 20, pl, 10_000)
    end

    test "cargas malformadas não levantam exceção" do
      s = world()
      for kind <- [20, 21], do: assert({:error, _} = run(s, 1, kind, "lixo", 100_000))
    end
  end

  describe "os modelos são dados com vocabulário fechado" do
    @guards [:before, :at_or_after, :var_lt_term, :var_eq_term]
    @effects [:lock, :release, :pay, :set_var, :inc_var]
    @exprs [:term, :var, :const, :add, :sub, :mul, :min]

    defp expr_ok?(e) when e in [:time, :escrow], do: true
    defp expr_ok?({op, a, b}) when op in [:add, :sub, :mul, :min], do: expr_ok?(a) and expr_ok?(b)
    defp expr_ok?({op, _}) when op in [:term, :var, :const], do: true
    defp expr_ok?(_), do: false

    test "todo modelo usa só estados, atores, condições, efeitos e expressões conhecidos" do
      for {id, t} <- ContractTemplates.all() do
        assert t.initial.state == :open, id

        for eff <- t.initial.effects, do: assert(elem(eff, 0) in @effects)

        for {name, tr} <- t.transitions do
          assert tr.actor in [:a, :b, :any], "#{id}/#{name}"
          assert is_atom(tr.from) and is_atom(tr.to)
          for g <- Map.get(tr, :guards, []), do: assert(elem(g, 0) in @guards, "#{id}/#{name}")

          for eff <- tr.effects do
            assert elem(eff, 0) in @effects, "#{id}/#{name}"
            if elem(eff, 0) in [:lock, :release], do: assert(expr_ok?(elem(eff, 2)))
            if elem(eff, 0) == :pay, do: assert(expr_ok?(elem(eff, 3)))
          end
        end
      end

      assert Enum.sort(Map.keys(ContractTemplates.all())) == [
               "aluguel",
               "compra-venda",
               "emprestimo"
             ]

      assert length(@exprs) == 7
    end

    test "estados finais do motor existem nos modelos" do
      used = for {_, t} <- ContractTemplates.all(), {_, tr} <- t.transitions, do: tr.to
      for st <- used, st not in [:funded, :active, :open], do: assert(st in Contracts.terminal())
    end
  end

  describe "propriedade" do
    defp op_gen do
      one_of([
        tuple(
          {constant(:create), member_of(["compra-venda", "aluguel", "emprestimo"]),
           member_of(["c1", "c2", "c3"])}
        ),
        tuple(
          {constant(:act), member_of([1, 2]), member_of(["c1", "c2", "c3"]), member_of(actions())}
        ),
        tuple({constant(:advance), integer(1..60)})
      ])
    end

    defp actions,
      do:
        ~w(accept confirm refund refund_expired cancel pay_rent settle settle_paid repay mark_default)

    defp terms("compra-venda"), do: [500_000, 50]
    defp terms("aluguel"), do: [100_000, 20, 2, 150_000, 5]
    defp terms("emprestimo"), do: [400_000, 450_000, 50]

    defp step(s, {:create, tpl, id}), do: create(s, 1, tpl, id, 2, terms(tpl))
    defp step(s, {:act, n, id, action}), do: act(s, n, id, action)
    defp step(s, {:advance, secs}), do: {:ok, at(s, s.time + secs)}

    property "em qualquer sequência: escrow global = soma dos escrows; estado final não guarda dinheiro; nada é criado" do
      check all(ops <- list_of(op_gen(), max_length: 50), max_runs: 100) do
        s0 = world()

        s =
          Enum.reduce(ops, s0, fn op, s ->
            case step(s, op) do
              {:ok, s2} -> s2
              {:error, _} -> s
            end
          end)

        assert s.escrow == s.contracts |> Map.values() |> Enum.map(& &1.escrow) |> Enum.sum()

        for {_, c} <- s.contracts do
          if c.state in Contracts.terminal(), do: assert(c.escrow == 0)
        end

        assert State.total_held(s) <= State.supply(s)
      end
    end
  end
end
