defmodule BrdcConsensus.ConsensusTest do
  use ExUnit.Case, async: true
  alias BrdcConsensus.{Certificate, Engine, Proposal, Sim, Vote}

  defp hashes(res),
    do: res.decisions |> Map.values() |> Enum.map(fn {_b, c} -> c.block_hash end) |> Enum.uniq()

  defp verify_all(res) do
    for {_i, {_block, cert}} <- res.decisions do
      assert :ok = Certificate.verify(cert, "sim", res.validators)
    end
  end

  describe "rede saudável" do
    test "4 validadores decidem o mesmo bloco, com certificado de mais de 2/3" do
      res = Sim.run(n: 4, seed: 1)
      assert map_size(res.decisions) == 4
      assert [_one] = hashes(res)
      verify_all(res)
      {_b, cert} = res.decisions[0]
      assert length(Certificate.signers(cert)) >= 3
    end

    test "é determinístico: mesma semente, mesmo resultado" do
      a = Sim.run(n: 4, seed: 7, delay: {1, 200})
      b = Sim.run(n: 4, seed: 7, delay: {1, 200})
      assert hashes(a) == hashes(b)
      assert a.time == b.time
    end

    test "1 validador sozinho decide" do
      res = Sim.run(n: 1)
      assert map_size(res.decisions) == 1
    end
  end

  describe "falhas" do
    test "proponente da rodada 0 fora do ar: a rodada seguinte tem outro proponente" do
      # altura 1, rodada 0: proponente = validador de índice 1
      res = Sim.run(n: 4, seed: 3, behaviors: %{1 => :silent})
      honest = [0, 2, 3]
      assert Enum.all?(honest, &Map.has_key?(res.decisions, &1))
      assert [_one] = hashes(res)
      {_b, cert} = res.decisions[0]
      assert cert.round >= 1
      verify_all(res)
    end

    test "sem quórum (2 de 4 fora do ar) a rede pausa em vez de bifurcar" do
      res = Sim.run(n: 4, seed: 4, behaviors: %{0 => :silent, 1 => :silent}, max_time: 60_000)
      assert res.decisions == %{}
    end

    test "partição 2×2 impede decisão e, ao curar, todos decidem o mesmo bloco" do
      res = Sim.run(n: 4, seed: 5, partition: {[[0, 1], [2, 3]], 20_000}, max_time: 300_000)
      assert map_size(res.decisions) == 4
      assert [_one] = hashes(res)
      assert res.time >= 20_000
      verify_all(res)
    end

    test "validador que equivoca não quebra a segurança" do
      res = Sim.run(n: 4, seed: 6, behaviors: %{2 => :equivocate}, max_time: 300_000)
      assert [_] = hashes(res)
      verify_all(res)
    end

    test "bloco inválido pelo ledger nunca é decidido" do
      res = Sim.run(n: 4, seed: 8, valid_fn: fn _ -> false end, max_time: 40_000)
      assert res.decisions == %{}
    end
  end

  describe "segurança por propriedade" do
    use ExUnitProperties

    property "com até 1/3 bizantino, nunca dois blocos finais na mesma altura (mesmo perdendo mensagens)" do
      check all(
              n <- member_of([4, 5, 6, 7]),
              seed <- integer(1..10_000),
              kinds <- list_of(member_of([:silent, :equivocate]), max_length: 2),
              drop <- member_of([0.0, 0.05, 0.2]),
              max_runs: 40
            ) do
        f = min(length(kinds), div(n - 1, 3))

        behaviors =
          kinds |> Enum.take(f) |> Enum.with_index() |> Map.new(fn {k, i} -> {i + 1, k} end)

        res = Sim.run(n: n, seed: seed, behaviors: behaviors, drop: drop, max_time: 60_000)
        assert length(hashes(res)) <= 1
        verify_all(res)
      end
    end

    property "sem perda de mensagens e com até 1/3 bizantino, todos os honestos decidem" do
      check all(
              n <- member_of([4, 7]),
              seed <- integer(1..10_000),
              kind <- member_of([:silent, :equivocate]),
              max_runs: 25
            ) do
        f = div(n - 1, 3)
        behaviors = for i <- 1..f, into: %{}, do: {i, kind}
        res = Sim.run(n: n, seed: seed, behaviors: behaviors, max_time: 300_000)
        honest = Enum.reject(0..(n - 1), &Map.has_key?(behaviors, &1))
        assert Enum.all?(honest, &Map.has_key?(res.decisions, &1))
        assert length(hashes(res)) == 1
      end
    end
  end

  describe "motor isolado" do
    setup do
      seeds = for i <- 0..3, do: :crypto.hash(:sha256, "sim-validator-#{i}")
      pubs = Enum.map(seeds, &BrdcCrypto.Ed25519.public_key/1)
      hash_fn = fn b -> BrdcCrypto.Hash.tagged("t", inspect(b)) end

      engine =
        Engine.new(
          chain_id: "c",
          height: 1,
          validators: pubs,
          seed: Enum.at(seeds, 0),
          hash_fn: hash_fn,
          valid_fn: fn _ -> true end
        )

      {:ok, engine: engine, seeds: seeds, pubs: pubs, hash_fn: hash_fn}
    end

    test "dois votos diferentes do mesmo validador na mesma rodada viram evidência", ctx do
      seed = Enum.at(ctx.seeds, 1)
      v1 = Vote.sign("c", :prevote, 1, 0, ctx.hash_fn.(:a), seed)
      v2 = Vote.sign("c", :prevote, 1, 0, ctx.hash_fn.(:b), seed)
      {e, _} = Engine.handle(ctx.engine, {:vote, v1})
      {_e, actions} = Engine.handle(e, {:vote, v2})
      assert [{:evidence, {^v1, ^v2}}] = Enum.filter(actions, &match?({:evidence, _}, &1))
    end

    test "voto com assinatura falsa, de estranho ou de outra altura é ignorado", ctx do
      good = Vote.sign("c", :prevote, 1, 0, nil, Enum.at(ctx.seeds, 1))
      forged = %{good | signature: <<0::512>>}
      stranger = Vote.sign("c", :prevote, 1, 0, nil, :crypto.hash(:sha256, "estranho"))
      other_height = Vote.sign("c", :prevote, 2, 0, nil, Enum.at(ctx.seeds, 1))
      other_chain = Vote.sign("outra", :prevote, 1, 0, nil, Enum.at(ctx.seeds, 1))

      for bad <- [forged, stranger, other_height, other_chain] do
        {e, _} = Engine.handle(ctx.engine, {:vote, bad})
        assert e.votes == %{}
      end
    end

    test "proposta de quem não é o proponente da rodada é ignorada", ctx do
      impostor = Enum.at(ctx.seeds, 2)
      p = Proposal.sign("c", 1, 0, -1, :x, ctx.hash_fn.(:x), impostor)
      {e, _} = Engine.handle(ctx.engine, {:proposal, p})
      assert e.proposals == %{}
    end

    test "proposta com bloco que não bate com o hash é ignorada", ctx do
      proposer = Enum.at(ctx.seeds, 1)
      p = Proposal.sign("c", 1, 0, -1, :x, ctx.hash_fn.(:y), proposer)
      {e, _} = Engine.handle(ctx.engine, {:proposal, p})
      assert e.proposals == %{}
    end

    test "inspect não mostra a chave privada", ctx do
      refute inspect(ctx.engine) =~ Base.encode16(ctx.engine.seed, case: :lower)
      assert inspect(ctx.engine) =~ "REDACTED"
    end
  end

  describe "certificado" do
    setup do
      res = Sim.run(n: 4, seed: 1)
      {_b, cert} = res.decisions[0]
      {:ok, cert: cert, vals: res.validators}
    end

    test "válido passa; faltando quórum, voto repetido, estranho e adulterado falham", %{
      cert: cert,
      vals: vals
    } do
      assert :ok = Certificate.verify(cert, "sim", vals)

      assert {:error, :no_quorum} =
               Certificate.verify(%{cert | votes: Enum.take(cert.votes, 2)}, "sim", vals)

      [v | _] = cert.votes

      assert {:error, :duplicate_voter} =
               Certificate.verify(%{cert | votes: [v | cert.votes]}, "sim", vals)

      assert {:error, :unknown_voter} =
               Certificate.verify(cert, "sim", tl(vals) ++ ([<<1::256>>] -- []))

      assert {:error, :bad_signature} =
               Certificate.verify(
                 %{cert | votes: [%{v | signature: <<0::512>>} | tl(cert.votes)]},
                 "sim",
                 vals
               )

      assert {:error, :different_block} =
               Certificate.verify(%{cert | block_hash: <<9::256>>}, "sim", vals)

      assert {:error, :bad_signature} = Certificate.verify(cert, "outra-rede", vals)
    end
  end
end
