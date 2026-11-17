defmodule BrdcLedger.AssetsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcLedger.{Approvals, Assets, Executor, Params, State, Tx}

  @chain "brdc-assets"
  @window 100

  defp seed(n), do: :crypto.hash(:sha256, "asset-seed-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))
  # 1-2: partes · 10-11: emissores · 20-21: autoridades raiz · 30-32: órgão da classe
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

  defp at(s, time), do: %{s | time: time}

  defp tx(s, n, kind, payload, fee) do
    t = %Tx{
      chain_id: @chain,
      kind: kind,
      nonce: State.account(s, addr(n)).nonce,
      fee: 0,
      sender_pub: Account.from_seed(seed(n)).public_key,
      payload: payload
    }

    fee = fee || Executor.min_fee(s.params, t)
    Tx.sign(%{t | fee: fee}, seed(n))
  end

  defp run(s, n, kind, payload, fee \\ nil) do
    case Executor.apply_tx(s, tx(s, n, kind, payload, fee)) do
      {:ok, s2, _fee} -> {:ok, s2}
      err -> err
    end
  end

  defp ok!({:ok, s}), do: s

  defp ap(doc, ns), do: for(n <- ns, do: Approvals.approval(doc, seed(n)))

  defp fund(s, n, amount) do
    ref = "fund-#{n}-#{s.minted}"
    doc = Tx.issuance_doc(:mint, @chain, addr(n), amount, ref)

    payload =
      Tx.issuance_payload(addr(n), amount, ref, for(i <- [10, 11], do: Tx.approval(doc, seed(i))))

    ok!(run(s, 99, 2, payload))
  end

  defp organ, do: [pub(30), pub(31), pub(32)]

  defp create_class(s, id \\ "imovel", window \\ @window, signers \\ [20, 21]) do
    d = Assets.class_doc(@chain, id, organ(), 2, window)
    run(s, 99, 5, Assets.class_payload(id, organ(), 2, window, ap(d, signers)))
  end

  defp register(
         s,
         asset,
         owner_n,
         signers \\ [30, 31],
         class \\ "imovel",
         meta \\ "matricula-123"
       ) do
    d = Assets.register_doc(@chain, class, asset, addr(owner_n), meta)
    run(s, 99, 6, Assets.register_payload(class, asset, addr(owner_n), meta, ap(d, signers)))
  end

  defp world do
    s = base() |> fund(1, 5_000_000) |> fund(2, 5_000_000) |> fund(99, 5_000_000)
    s = ok!(create_class(s))
    ok!(register(s, "casa-1", 1))
  end

  defp offer(s, price \\ 1_000_000),
    do: run(s, 1, 7, Assets.offer_payload("casa-1", addr(2), price))

  defp accept(s), do: run(s, 2, 8, Assets.asset_payload("casa-1"))
  defp finalize(s), do: run(s, 99, 11, Assets.asset_payload("casa-1"))

  defp veto(s, signers \\ [30, 31]) do
    asset = s.assets["casa-1"]
    deal = s.deals["casa-1"]
    d = Assets.veto_doc(@chain, "casa-1", asset.rev, deal.buyer, deal.price, deal.deadline || 0)
    run(s, 99, 10, Assets.veto_payload("casa-1", ap(d, signers)))
  end

  defp lien_add(s, lien \\ "penhora-1", ref \\ "proc-9", signers \\ [30, 31]) do
    d = Assets.lien_add_doc(@chain, "casa-1", s.assets["casa-1"].rev, lien, ref)
    run(s, 99, 12, Assets.lien_add_payload("casa-1", lien, ref, ap(d, signers)))
  end

  defp lien_remove(s, lien \\ "penhora-1") do
    a = s.assets["casa-1"]
    d = Assets.lien_remove_doc(@chain, "casa-1", a.rev, lien, a.liens[lien] || "")
    run(s, 99, 13, Assets.lien_remove_payload("casa-1", lien, ap(d, [30, 31])))
  end

  describe "classe e registro" do
    test "autoridades raiz criam a classe e o órgão registra o bem" do
      s = world()
      assert s.classes["imovel"].veto_window == @window
      assert %{owner: o, rev: 0} = s.assets["casa-1"]
      assert o == addr(1)
    end

    test "classe: aprovações insuficientes, sem autoridade, duplicada, janela fora do limite, id ruim" do
      s = fund(base(), 99, 1_000_000)
      assert {:error, :not_enough_approvals} = create_class(s, "imovel", @window, [20])
      assert {:error, :not_enough_approvals} = create_class(s, "imovel", @window, [20, 30])
      assert {:error, :bad_class} = create_class(s, "imovel", 0)
      assert {:error, :bad_class} = create_class(s, "imovel", 99_999_999_999)
      assert {:error, :bad_id} = create_class(s, "")
      assert {:error, :bad_id} = create_class(s, String.duplicate("a", 33))
      s2 = ok!(create_class(s))
      assert {:error, :class_exists} = create_class(s2)

      {:ok, p} = Params.new(chain_id: @chain, issuers: [pub(10)], threshold: 1)
      s0 = p |> State.new() |> fund(99, 1_000_000)
      assert {:error, :no_authority} = create_class(s0)
    end

    test "registro: precisa do órgão da classe (M-de-N), classe existente, id único" do
      s = ok!(create_class(fund(base(), 99, 1_000_000)))
      assert {:error, :not_enough_approvals} = register(s, "x", 1, [30])
      assert {:error, :not_enough_approvals} = register(s, "x", 1, [20, 21])
      assert {:error, :no_class} = register(s, "x", 1, [30, 31], "outra")
      assert {:error, :bad_id} = register(s, String.duplicate("a", 65), 1)

      assert {:error, :bad_id} =
               register(s, "x", 1, [30, 31], "imovel", String.duplicate("m", 257))

      s2 = ok!(register(s, "x", 1))
      assert {:error, :asset_exists} = register(s2, "x", 2)
    end

    test "aprovação de um bem não vale para outro dono ou outro metadado" do
      s = ok!(create_class(fund(base(), 99, 1_000_000)))
      d = Assets.register_doc(@chain, "imovel", "x", addr(1), "m")
      forged = Assets.register_payload("imovel", "x", addr(2), "m", ap(d, [30, 31]))
      assert {:error, :not_enough_approvals} = run(s, 99, 6, forged)
    end
  end

  describe "negociação" do
    test "oferta, aceite com escrow, prazo, finalização: a propriedade passa e o vendedor recebe" do
      s = at(world(), 1_000)
      s = ok!(offer(s))
      s = ok!(accept(s))
      assert s.escrow == 1_000_000
      assert s.deals["casa-1"].deadline == 1_000 + @window

      # taxas pagas até aqui: classe 50k + registro 50k + oferta 20k + aceite 20k (o bloco as repartiria)
      assert State.total_held(s) + 140_000 == State.supply(s)

      assert {:error, :window_open} = finalize(at(s, 1_099))
      s = ok!(finalize(at(s, 1_100)))

      assert s.assets["casa-1"].owner == addr(2)
      assert s.escrow == 0 and s.deals == %{}
      # + finalização 20k
      assert State.total_held(s) + 160_000 == State.supply(s)
      assert State.balance(s, addr(1)) > 5_000_000
    end

    test "só o dono oferta, só o comprador aceita, sem fundos não aceita, não oferta a si mesmo" do
      s = world()
      assert {:error, :not_owner} = run(s, 2, 7, Assets.offer_payload("casa-1", addr(2), 1))
      assert {:error, :self_deal} = run(s, 1, 7, Assets.offer_payload("casa-1", addr(1), 1))
      assert {:error, :no_asset} = run(s, 1, 7, Assets.offer_payload("nao-existe", addr(2), 1))
      s1 = ok!(offer(s))
      assert {:error, :deal_active} = offer(s1)
      assert {:error, :not_buyer} = run(s1, 1, 8, Assets.asset_payload("casa-1"))
      assert {:error, :no_deal} = run(s, 2, 8, Assets.asset_payload("casa-1"))

      s2 = ok!(offer(s, 900_000_000))
      assert {:error, :insufficient_funds} = accept(s2)
    end

    test "o dono cancela só antes do aceite" do
      s = ok!(offer(world()))
      assert {:error, :not_owner} = run(s, 2, 9, Assets.asset_payload("casa-1"))
      assert %{deals: d} = ok!(run(s, 1, 9, Assets.asset_payload("casa-1")))
      assert d == %{}

      s2 = ok!(accept(s))
      assert {:error, :bad_status} = run(s2, 1, 9, Assets.asset_payload("casa-1"))
      assert {:error, :bad_status} = accept(s2)
    end

    test "finalizar sem aceite é recusado" do
      s = ok!(offer(world()))
      assert {:error, :bad_status} = finalize(at(s, 10_000))
    end
  end

  describe "em bloco" do
    alias BrdcLedger.Block

    test "oferta e aceite no mesmo bloco: as taxas são repartidas e saldos + escrow = oferta" do
      s = at(world(), 1_000)
      validator = addr(50)
      o = tx(s, 1, 7, Assets.offer_payload("casa-1", addr(2), 1_000_000), nil)
      s_after_offer = ok!(Executor.apply_tx(s, o) |> then(fn {:ok, st, _} -> {:ok, st} end))
      a = tx(s_after_offer, 2, 8, Assets.asset_payload("casa-1"), nil)

      assert {:ok, block, s2} = Block.build(s, validator, [validator], [o, a], 1_050)
      assert s2.escrow == 1_000_000
      assert s2.deals["casa-1"].deadline == 1_050 + @window
      # o bloco repartiu as taxas (20k + 20k) com quem assinou: nada fica no ar
      assert State.balance(s2, validator) == 40_000

      # só ficam "no ar" as taxas de classe e registro, pagas antes sem bloco
      assert State.total_held(s2) == State.supply(s2) - fees_before(s)

      assert {:ok, s3} = Block.apply(s, block)
      assert State.root(s3) == State.root(s2)
    end

    # taxas já pagas e ainda não repartidas antes deste bloco (classe + registro, sem bloco)
    defp fees_before(s), do: State.supply(s) - State.total_held(s)
  end

  describe "veto do órgão" do
    test "dentro da janela, devolve o escrow ao comprador e a propriedade não muda" do
      s = at(world(), 50)
      s = ok!(accept(ok!(offer(s))))
      before = State.balance(s, addr(2))
      s = ok!(veto(at(s, 100)))
      assert State.balance(s, addr(2)) == before + 1_000_000
      assert s.escrow == 0 and s.deals == %{}
      assert s.assets["casa-1"].owner == addr(1)
      assert s.assets["casa-1"].rev == 1
      assert State.total_held(s) + 140_000 == State.supply(s)
    end

    test "depois do prazo o veto é recusado" do
      s = at(world(), 50)
      s = ok!(accept(ok!(offer(s))))
      assert {:error, :window_closed} = veto(at(s, 150))
    end

    test "aprovações insuficientes ou de quem não é do órgão não vetam" do
      s = ok!(accept(ok!(offer(at(world(), 50)))))
      assert {:error, :not_enough_approvals} = veto(s, [30])
      assert {:error, :not_enough_approvals} = veto(s, [1, 2])
    end

    test "uma aprovação de veto não vale para outra negociação (comprador, preço e prazo amarrados)" do
      s = at(world(), 50)
      s1 = ok!(accept(ok!(offer(s))))
      deal = s1.deals["casa-1"]
      d = Assets.veto_doc(@chain, "casa-1", 0, deal.buyer, deal.price, deal.deadline)
      stale = Assets.veto_payload("casa-1", ap(d, [30, 31]))

      # nova negociação com outro preço: a aprovação antiga não serve
      s2 = ok!(veto(at(s1, 60)))
      s2 = ok!(accept(ok!(offer(at(s2, 70), 2_000_000))))
      assert {:error, :not_enough_approvals} = run(at(s2, 80), 99, 10, stale)
    end
  end

  describe "gravames" do
    test "gravame bloqueia oferta; remover libera" do
      s = ok!(lien_add(world()))
      assert map_size(s.assets["casa-1"].liens) == 1
      assert {:error, :has_lien} = offer(s)
      s = ok!(lien_remove(s))
      assert {:ok, _} = offer(s)
    end

    test "gravame durante a janela impede a finalização até ser removido" do
      s = at(world(), 10)
      s = ok!(accept(ok!(offer(s))))
      s = ok!(lien_add(s))
      assert {:error, :has_lien} = finalize(at(s, 500))
      s = ok!(lien_remove(s))
      assert {:ok, s} = finalize(at(s, 500))
      assert s.assets["casa-1"].owner == addr(2)
    end

    test "a aprovação de um gravame não pode ser repetida" do
      s = world()
      d = Assets.lien_add_doc(@chain, "casa-1", 0, "penhora-1", "proc-9")
      payload = Assets.lien_add_payload("casa-1", "penhora-1", "proc-9", ap(d, [30, 31]))
      s = ok!(run(s, 99, 12, payload))
      s = ok!(lien_remove(s))
      # mesma aprovação (rev 0) depois de a revisão subir: não vale mais
      assert {:error, :not_enough_approvals} = run(s, 99, 12, payload)
    end

    test "gravame duplicado, inexistente e sem aprovação do órgão" do
      s = ok!(lien_add(world()))
      assert {:error, :lien_exists} = lien_add(s)
      assert {:error, :no_lien} = lien_remove(s, "outro")
      assert {:error, :not_enough_approvals} = lien_add(world(), "p", "r", [30])
      assert {:error, :bad_id} = lien_add(world(), "", "r")
    end
  end

  describe "taxas (ADR-0014/0018)" do
    test "registro e classe 0,05; etapas 0,02; ações do órgão sem taxa mínima" do
      s = world()
      p = s.params

      mk = fn k ->
        %Tx{chain_id: @chain, kind: k, nonce: 0, fee: 0, sender_pub: pub(1), payload: ""}
      end

      assert Enum.map([5, 6], &Executor.min_fee(p, mk.(&1))) == [50_000, 50_000]

      assert Enum.map([7, 8, 9, 11], &Executor.min_fee(p, mk.(&1))) == [
               20_000,
               20_000,
               20_000,
               20_000
             ]

      assert Enum.map([10, 12, 13], &Executor.min_fee(p, mk.(&1))) == [0, 0, 0]
    end

    test "taxa abaixo do mínimo é recusada" do
      s = world()

      assert {:error, :fee_too_low} =
               run(s, 1, 7, Assets.offer_payload("casa-1", addr(2), 1), 19_999)
    end
  end

  test "carga malformada é recusada sem exceção" do
    s = world()

    for kind <- 5..13 do
      assert {:error, _} = run(s, 1, kind, "lixo", 100_000)
    end
  end

  describe "propriedades" do
    defp step_gen do
      one_of([
        tuple({constant(:offer), integer(0..2_000_000)}),
        constant(:accept),
        constant(:cancel),
        constant(:veto),
        constant(:finalize),
        constant(:lien_add),
        constant(:lien_remove),
        tuple({constant(:advance), integer(1..80)})
      ])
    end

    defp try_step(s, {:offer, price}), do: offer(s, price)
    defp try_step(s, :accept), do: accept(s)
    defp try_step(s, :cancel), do: run(s, 1, 9, Assets.asset_payload("casa-1"))
    defp try_step(s, :finalize), do: finalize(s)
    defp try_step(s, :lien_add), do: lien_add(s, "p#{s.assets["casa-1"].rev}")
    defp try_step(s, {:advance, secs}), do: {:ok, at(s, s.time + secs)}

    defp try_step(s, :veto) do
      if s.deals["casa-1"], do: veto(s), else: {:error, :no_deal}
    end

    defp try_step(s, :lien_remove) do
      case Map.keys(s.assets["casa-1"].liens) do
        [lien | _] -> lien_remove(s, lien)
        [] -> {:error, :no_lien}
      end
    end

    property "em qualquer sequência: saldos + escrow = oferta; escrow = soma dos negócios aceitos; sempre há um dono" do
      check all(steps <- list_of(step_gen(), max_length: 30), max_runs: 80) do
        s0 = at(world(), 1_000)

        s =
          Enum.reduce(steps, s0, fn step, s ->
            case try_step(s, step) do
              {:ok, s2} -> s2
              {:error, _} -> s
            end
          end)

        accepted = for {_, %{status: :accepted, price: p}} <- s.deals, do: p
        assert s.escrow == Enum.sum(accepted)

        # as taxas pagas saem das contas e não voltam (ninguém assinou o bloco): só conferimos o teto
        assert State.total_held(s) <= State.supply(s)
        assert s.assets["casa-1"].owner in [addr(1), addr(2)]
        assert s.escrow >= 0
      end
    end
  end
end
