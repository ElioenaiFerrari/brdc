defmodule BrdcDev.SimulationTest do
  # a produção da moeda de ponta a ponta, dentro da VM: nó com blocos automáticos, porta pública e as ferramentas
  use ExUnit.Case, async: false
  alias BrdcDev.{Chain, Devnet, Issuance, Simulation, Wallets}
  alias BrdcNode.{Client, Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  setup %{tmp_dir: dir} do
    {:ok, devnet} = Devnet.ensure(dir)

    {:ok, node} =
      Node.start_link(genesis: devnet.genesis, seed: devnet.seeds["v1"], block_interval_ms: 20)

    {:ok, guard} = Guard.start_link(sweep_ms: :never)
    {:ok, port} = PublicPort.start_link(guard: guard, handler: Handler.fun(node), port: 0)
    on_exit(fn -> catch_exit(PublicPort.stop(port)) end)
    %{devnet: devnet, endpoint: {~c"127.0.0.1", PublicPort.port(port)}, dir: dir}
  end

  test "o cenário completo roda e confere as regras (reserva, mint 2 de 2, transferência, resgate)",
       ctx do
    lines = :ets.new(:sim_lines, [:public, :ordered_set])
    out = fn line -> :ets.insert(lines, {System.unique_integer([:monotonic]), line}) end

    assert {:ok, %{final: final, alice: alice, bob: bob}} =
             Simulation.issuance(ctx.endpoint, ctx.devnet, ctx.dir, out)

    text = lines |> :ets.tab2list() |> Enum.map_join("\n", &elem(&1, 1))

    assert final.supply == 750_000_000
    assert final.minted == 1_000_000_000 and final.burned == 250_000_000
    assert final.attestation.reserve == 750_000_000 and final.attestation.seq == 2
    assert final.coverage == {:covered, 0}
    assert bob == 0
    # a Alice tem 750 menos a taxa (que foi aos validadores)
    assert alice < 750_000_000 and alice > 749_900_000
    assert text =~ "recusado, como deve ser"
    assert text =~ "ok: oferta, reserva"
  end

  test "rodar o cenário duas vezes seguidas também fecha (ele trabalha com variações)", ctx do
    quiet = fn _ -> :ok end
    assert {:ok, _} = Simulation.issuance(ctx.endpoint, ctx.devnet, ctx.dir, quiet)
    assert {:ok, %{final: f}} = Simulation.issuance(ctx.endpoint, ctx.devnet, ctx.dir, quiet)
    assert f.supply == 2 * 750_000_000
    assert f.attestation.seq == 4
  end

  test "mint com só um emissor é recusado; com os dois, aceito", ctx do
    {:ok, w} = Wallets.create(ctx.dir, "dest")
    hash = Wallets.hash({:wallet, w})

    assert {:error, _} =
             Issuance.mint_with(ctx.endpoint, ctx.devnet, hash, 1_000_000, "so-um", ["i1"])

    assert {:error, _} =
             Issuance.mint_with(ctx.endpoint, ctx.devnet, hash, 1_000_000, "so-outro", ["i2"])

    assert {:ok, sent} = Issuance.mint(ctx.endpoint, ctx.devnet, hash, 1_000_000, "dois")
    assert :ok = Chain.await_included(ctx.endpoint, sent.sender, sent.nonce)
    assert {:ok, 1_000_000} = Chain.balance(ctx.endpoint, hash)
    # a mesma referência não vale duas vezes
    assert {:error, _} = Issuance.mint(ctx.endpoint, ctx.devnet, hash, 1_000_000, "dois")
  end

  test "resgate: só o dono queima; não dá para queimar mais do que tem; a oferta cai", ctx do
    {:ok, w} = Wallets.create(ctx.dir, "holder")
    hash = Wallets.hash({:wallet, w})
    {:ok, m} = Issuance.mint(ctx.endpoint, ctx.devnet, hash, 5_000_000, "dep")
    :ok = Chain.await_included(ctx.endpoint, m.sender, m.nonce)

    assert {:error, _} =
             Issuance.burn(ctx.endpoint, ctx.devnet, w.account.seed, 6_000_000, "demais")

    assert {:ok, b} = Issuance.burn(ctx.endpoint, ctx.devnet, w.account.seed, 2_000_000, "ok")
    assert :ok = Chain.await_included(ctx.endpoint, b.sender, b.nonce)
    assert {:ok, 3_000_000} = Chain.balance(ctx.endpoint, hash)

    assert {:ok, %{supply: 3_000_000, minted: 5_000_000, burned: 2_000_000}} =
             Client.supply(ctx.endpoint)
  end

  test "atestado de reserva: sequência automática, cobertura exata, coberta e abaixo", ctx do
    {:ok, w} = Wallets.create(ctx.dir, "x")
    hash = Wallets.hash({:wallet, w})
    {:ok, m} = Issuance.mint(ctx.endpoint, ctx.devnet, hash, 10_000_000, "d")
    :ok = Chain.await_included(ctx.endpoint, m.sender, m.nonce)
    assert {:ok, %{coverage: :none, attestation: nil}} = Client.supply(ctx.endpoint)

    for {reserve, seq, coverage} <- [
          {10_000_000, 1, {:covered, 0}},
          {15_000_000, 2, {:covered, 5_000_000}},
          {4_000_000, 3, {:under, 6_000_000}}
        ] do
      {:ok, a} = Issuance.attest(ctx.endpoint, ctx.devnet, reserve, "att-#{seq}")
      :ok = Chain.await_included(ctx.endpoint, a.sender, a.nonce)

      assert {:ok, %{attestation: %{seq: ^seq, reserve: ^reserve}, coverage: ^coverage}} =
               Client.supply(ctx.endpoint)
    end
  end

  test "o texto da cobertura é claro nos três casos" do
    assert Simulation.coverage(:none) == "sem atestado"
    assert Simulation.coverage({:covered, 0}) =~ "exata"
    assert Simulation.coverage({:covered, 5_000_000}) =~ "sobra R$ 5,00"
    assert Simulation.coverage({:under, 2_500_000}) =~ "ABAIXO: faltam R$ 2,50"
  end
end
