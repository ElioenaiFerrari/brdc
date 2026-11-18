defmodule BrdcConsensus.RestoreTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcConsensus.{Engine, Proposal, Sim, Vote}
  alias BrdcCrypto.{Ed25519, Hash}

  @chain "sim"

  defp seeds, do: for(i <- 0..3, do: :crypto.hash(:sha256, "sim-validator-#{i}"))
  defp pubs, do: Enum.map(seeds(), &Ed25519.public_key/1)
  defp hash_fn, do: fn block -> Hash.tagged("brdc/sim/block", inspect(block)) end

  defp engine(i) do
    Engine.new(
      chain_id: @chain,
      height: 1,
      validators: pubs(),
      seed: Enum.at(seeds(), i),
      hash_fn: hash_fn(),
      valid_fn: fn _ -> true end
    )
  end

  # proposta de `i` na rodada `r`
  defp proposal(i, r, block, valid_round \\ -1) do
    Proposal.sign(@chain, 1, r, valid_round, block, hash_fn().(block), Enum.at(seeds(), i))
  end

  defp vote(i, type, r, block),
    do: Vote.sign(@chain, type, 1, r, block && hash_fn().(block), Enum.at(seeds(), i))

  defp broadcasts(actions), do: for({:broadcast, m} <- actions, do: m)

  describe "codificação" do
    test "voto: ida e volta (com e sem bloco) e recusa de lixo" do
      for h <- [nil, :crypto.hash(:sha256, "x")] do
        v = Vote.sign(@chain, :precommit, 7, 3, h, hd(seeds()))
        assert {:ok, ^v} = Vote.decode(Vote.encode(v))
        assert Vote.valid?(@chain, elem(Vote.decode(Vote.encode(v)), 1))
      end

      v = vote(0, :prevote, 0, {:txs, 1})
      bin = Vote.encode(v)
      assert {:error, :malformed} = Vote.decode(bin <> <<0>>)
      assert {:error, :malformed} = Vote.decode(binary_part(bin, 0, byte_size(bin) - 1))
      assert {:error, :malformed} = Vote.decode(<<9>> <> binary_part(bin, 1, byte_size(bin) - 1))
      assert {:error, :malformed} = Vote.decode("lixo")
    end

    test "proposta: ida e volta, valid_round -1 incluído, e recusa de lixo" do
      enc = fn b -> :erlang.term_to_binary(b) end
      dec = fn bin -> {:ok, :erlang.binary_to_term(bin, [:safe])} end

      for vr <- [-1, 0, 5] do
        p = proposal(1, 2, {:txs, 9}, vr)
        assert {:ok, ^p} = Proposal.decode(Proposal.encode(p, enc), dec)
      end

      bin = Proposal.encode(proposal(1, 0, {:txs, 1}), enc)
      assert {:error, :malformed} = Proposal.decode(bin <> <<0>>, dec)
      assert {:error, :malformed} = Proposal.decode(binary_part(bin, 0, 20), dec)
      assert {:error, :malformed} = Proposal.decode(bin, fn _ -> {:error, :x} end)
    end
  end

  describe "reenvio a quem (re)conecta" do
    test "known_messages devolve propostas e votos de todos os validadores, só das últimas rodadas" do
      {e, _} = Engine.start(engine(2))
      {e, _} = Engine.handle(e, {:proposal, proposal(1, 0, {:txs, :b})})
      {e, _} = Engine.handle(e, {:vote, vote(0, :prevote, 0, {:txs, :b})})
      msgs = Engine.known_messages(e)
      assert Enum.count(msgs, &match?(%Proposal{}, &1)) == 1
      # o prevote próprio (validador 2) e o do validador 0
      assert msgs |> Enum.filter(&match?(%Vote{}, &1)) |> Enum.map(& &1.voter) |> Enum.sort() ==
               Enum.sort([Enum.at(pubs(), 0), Enum.at(pubs(), 2)])

      # reentregar a mesma coisa a outro motor é inofensivo: ele chega ao mesmo estado e não assina nada novo
      {fresh, _} = Engine.start(engine(3))

      {fresh, acts} =
        Enum.reduce(msgs, {fresh, []}, fn
          %Proposal{} = p, {eng, a} ->
            (fn {e2, x} -> {e2, a ++ x} end).(Engine.handle(eng, {:proposal, p}))

          %Vote{} = v, {eng, a} ->
            (fn {e2, x} -> {e2, a ++ x} end).(Engine.handle(eng, {:vote, v}))
        end)

      {again, acts2} =
        Enum.reduce(msgs, {fresh, []}, fn
          %Proposal{} = p, {eng, a} ->
            (fn {e2, x} -> {e2, a ++ x} end).(Engine.handle(eng, {:proposal, p}))

          %Vote{} = v, {eng, a} ->
            (fn {e2, x} -> {e2, a ++ x} end).(Engine.handle(eng, {:vote, v}))
        end)

      assert {again.round, again.step} == {fresh.round, fresh.step}
      assert broadcasts(acts2) == []
      assert is_list(acts)
    end
  end

  describe "por que o diário existe" do
    # validador 2 (não propõe a rodada 0 da altura 1) prevota no bloco B e cai
    setup do
      {e, _} = Engine.start(engine(2))
      {e, acts} = Engine.handle(e, {:proposal, proposal(1, 0, {:txs, :b})})
      [prevote] = broadcasts(acts)
      %{engine: e, journal: [prevote], prevote: prevote}
    end

    test "SEM diário, ao voltar ele prevota nulo na mesma rodada: equivocação", %{prevote: first} do
      {fresh, _} = Engine.start(engine(2))
      {_e, acts} = Engine.handle(fresh, {:timeout, :propose, 0})
      [second] = broadcasts(acts)
      assert second.type == first.type and second.round == first.round
      refute second.block_hash == first.block_hash
    end

    test "COM diário, ele volta no mesmo passo e não assina nada que contradiga", %{
      journal: j,
      prevote: first
    } do
      {e, acts} = Engine.restore(engine(2), j)
      assert e.round == 0 and e.step == :prevote
      # só pede o prazo de prevote; não transmite nada
      assert broadcasts(acts) == []
      assert {:schedule_timeout, :prevote, 0} in acts

      # o prazo da proposta já passou para ele: ignorado, e nenhum voto novo
      {e, acts} = Engine.handle(e, {:timeout, :propose, 0})
      assert broadcasts(acts) == []
      # o prazo de prevote leva ao precommit nulo, que não conflita com nada
      {_e, acts} = Engine.handle(e, {:timeout, :prevote, 0})
      assert [%Vote{type: :precommit, block_hash: nil}] = broadcasts(acts)
      assert first.type == :prevote
    end

    test "mensagens de outros validadores e de outra altura no diário são ignoradas", %{
      journal: j
    } do
      other = [
        vote(0, :prevote, 0, {:txs, :b}),
        %{Vote.sign(@chain, :prevote, 9, 0, nil, Enum.at(seeds(), 2)) | height: 9}
      ]

      {e, _} = Engine.restore(engine(2), other ++ j)
      assert e.round == 0 and e.step == :prevote
      # o voto de outro (validador 0) NÃO foi guardado como se fosse nosso
      refute e.votes[{:prevote, 0}] |> Map.has_key?(Enum.at(pubs(), 0))
    end

    test "restaurar duas vezes dá o mesmo estado (idempotente)", %{journal: j} do
      {a, _} = Engine.restore(engine(2), j)
      {b, _} = Engine.restore(engine(2), j ++ j)
      assert {a.round, a.step, a.locked} == {b.round, b.step, b.locked}
    end
  end

  describe "o bloqueio sobrevive à queda" do
    # validador 3: vê a proposta B, mais 2 prevotes em B (de 0 e 1), trava em B e dá precommit em B
    setup do
      {e, a1} = Engine.start(engine(3))
      {e, a2} = Engine.handle(e, {:proposal, proposal(1, 0, {:txs, :b})})
      {e, a3} = Engine.handle(e, {:vote, vote(0, :prevote, 0, {:txs, :b})})
      {e, a4} = Engine.handle(e, {:vote, vote(1, :prevote, 0, {:txs, :b})})
      journal = broadcasts(a1 ++ a2 ++ a3 ++ a4)
      assert %{locked: {_, 0}} = e
      %{journal: journal}
    end

    test "restaurado, ele continua travado em B e prevota nulo numa proposta nova de C", %{
      journal: j
    } do
      {e, _} = Engine.restore(engine(3), j)
      assert {_, 0} = e.locked
      assert e.step == :precommit

      # passa à rodada 1; o proponente (validador 2) propõe outro bloco C, sem prova de rodada nova
      {e, _} = Engine.handle(e, {:timeout, :precommit, 0})
      assert e.round == 1
      {_e, acts} = Engine.handle(e, {:proposal, proposal(2, 1, {:txs, :c})})
      assert [%Vote{type: :prevote, round: 1, block_hash: nil}] = broadcasts(acts)
    end

    test "SEM diário o bloqueio se perde e ele prevotaria C (o que quebra a segurança)" do
      {e, _} = Engine.start(engine(3))
      {e, _} = Engine.handle(e, {:timeout, :propose, 0})
      {e, _} = Engine.handle(e, {:timeout, :prevote, 0})
      {e, _} = Engine.handle(e, {:timeout, :precommit, 0})
      assert e.round == 1 and e.locked == nil
      {_e, acts} = Engine.handle(e, {:proposal, proposal(2, 1, {:txs, :c})})
      assert [%Vote{type: :prevote, block_hash: h}] = broadcasts(acts)
      assert h == hash_fn().({:txs, :c})
    end
  end

  describe "simulação com quedas" do
    # atraso largo: a decisão leva centenas de ms, então a queda cai no meio da rodada
    @slow {5, 300}

    property "com 1 queda aleatória e diário, nunca há equivocação e nunca dois blocos finais" do
      check all(
              seed <- StreamData.integer(1..10_000),
              node <- StreamData.integer(0..3),
              at <- StreamData.integer(0..600),
              down <- StreamData.integer(0..2_500),
              max_runs: 80
            ) do
        r = Sim.run(n: 4, seed: seed, delay: @slow, crashes: [{node, at, down}], max_time: 40_000)
        assert r.evidence == []
        blocks = r.decisions |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
        assert length(blocks) <= 1
      end
    end

    property "com 2 quedas em nós diferentes, segurança mantida" do
      check all(
              seed <- StreamData.integer(1..10_000),
              {a, b} <- StreamData.member_of([{0, 1}, {1, 2}, {2, 3}, {0, 3}]),
              t1 <- StreamData.integer(0..400),
              t2 <- StreamData.integer(0..400),
              max_runs: 50
            ) do
        crashes = [{a, t1, 800}, {b, t2 + 1_500, 800}]
        r = Sim.run(n: 4, seed: seed, delay: @slow, crashes: crashes, max_time: 40_000)
        assert r.evidence == []

        assert r.decisions |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() <=
                 1
      end
    end

    test "as quedas dos testes acontecem de fato (não são vazias): na maioria das sementes há reinício" do
      restarted =
        Enum.count(1..40, fn seed ->
          Sim.run(n: 4, seed: seed, delay: @slow, crashes: [{2, 60, 200}], max_time: 40_000).restarts ==
            1
        end)

      assert restarted >= 30
    end

    test "um nó que cai logo depois de prevotar e volta com diário ainda leva a altura a uma decisão única" do
      results =
        for seed <- 1..40,
            do: Sim.run(n: 4, seed: seed, delay: @slow, crashes: [{2, 80, 300}], max_time: 60_000)

      assert Enum.all?(results, &(&1.evidence == []))

      assert Enum.all?(results, fn r ->
               r.decisions |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() ==
                 1
             end)

      # os 3 que não caíram sempre chegam a decidir (quórum de 3 de 4)
      assert Enum.all?(results, &(map_size(&1.decisions) >= 3))
    end
  end
end
