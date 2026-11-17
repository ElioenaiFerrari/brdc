defmodule BrdcNode.GenesisTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcNode.Genesis

  defp key(n), do: :crypto.hash(:sha256, "genesis-key-#{n}")

  defp base(overrides \\ []) do
    Keyword.merge(
      [
        chain_id: "brdc-devnet",
        validators: [key(1), key(2), key(3)],
        issuers: [key(10), key(11)],
        threshold: 2,
        bootstrap: [%{validator: key(1), host: "127.0.0.1", port: 4001}]
      ],
      overrides
    )
  end

  defp g!(overrides \\ []) do
    {:ok, g} = Genesis.new(base(overrides))
    g
  end

  test "cria, serializa e lê de volta idêntica, com o mesmo hash" do
    g = g!()
    assert {:ok, ^g} = Genesis.from_json(Genesis.to_json(g))
    assert Genesis.hash(g) == Genesis.hash(g!())
  end

  test "autoridades e taxas de bens sobrevivem à ida e volta do JSON" do
    g = g!(authorities: [key(20), key(21)], authority_threshold: 2, asset_step_fee: 33)
    assert {:ok, ^g} = Genesis.from_json(Genesis.to_json(g))
  end

  test "qualquer campo diferente muda o hash (redes diferentes se recusam)" do
    h = Genesis.hash(g!())

    for o <- [
          [chain_id: "outra"],
          [validators: [key(1), key(3), key(2)]],
          [validators: [key(1), key(2)]],
          [issuers: [key(10), key(12)]],
          [threshold: 1],
          [transfer_base: 2_000],
          [per_byte: 2],
          [max_block_txs: 10],
          [max_block_bytes: 1_000],
          [authorities: [key(20)]],
          [authorities: [key(20), key(21)], authority_threshold: 2],
          [asset_register_fee: 1],
          [asset_step_fee: 1],
          [contest_window: 120],
          [veto_window: 120],
          [min_window: 30],
          [max_window: 1_000_000],
          [bootstrap: []]
        ] do
      refute Genesis.hash(g!(o)) == h, "esperava hash diferente para #{inspect(o)}"
    end
  end

  test "a ordem dos validadores muda o hash (define o rodízio)" do
    refute Genesis.hash(g!(validators: [key(1), key(2), key(3)])) ==
             Genesis.hash(g!(validators: [key(3), key(2), key(1)]))
  end

  test "valida tudo" do
    assert {:error, :bad_chain_id} = Genesis.new(base(chain_id: "tem espaço"))
    assert {:error, :bad_chain_id} = Genesis.new(base(chain_id: ""))
    assert {:error, :bad_validators} = Genesis.new(base(validators: []))
    assert {:error, :bad_validators} = Genesis.new(base(validators: [key(1), key(1)]))
    assert {:error, :bad_validators} = Genesis.new(base(validators: [<<1, 2>>]))
    assert {:error, :bad_issuers} = Genesis.new(base(issuers: []))
    assert {:error, :bad_threshold} = Genesis.new(base(threshold: 3))
    assert {:error, :bad_threshold} = Genesis.new(base(threshold: 0))
    assert {:error, :bad_fees} = Genesis.new(base(per_byte: -1))
    assert {:error, :bad_block_limits} = Genesis.new(base(max_block_txs: 0))
    assert {:error, :bad_authorities} = Genesis.new(base(authorities: [key(20), key(20)]))

    assert {:error, :bad_authorities} =
             Genesis.new(base(authorities: [key(20)], authority_threshold: 2))

    assert {:error, :bad_authorities} = Genesis.new(base(authorities: [<<1>>]))
    assert {:error, :bad_fees} = Genesis.new(base(asset_step_fee: -1))
    assert {:ok, _} = Genesis.new(base(authorities: [key(20), key(21)], authority_threshold: 2))
    assert {:error, :bad_windows} = Genesis.new(base(contest_window: 10))
    assert {:error, :bad_windows} = Genesis.new(base(veto_window: 99_999_999_999))
    assert {:error, :bad_windows} = Genesis.new(base(min_window: 0))
    assert {:error, :bad_windows} = Genesis.new(base(min_window: 100, max_window: 50))
    assert {:ok, _} = Genesis.new(base(contest_window: 60, veto_window: 60, min_window: 1))

    assert {:error, :bad_bootstrap} =
             Genesis.new(base(bootstrap: [%{validator: key(99), host: "a.b", port: 1}]))

    assert {:error, :bad_bootstrap} =
             Genesis.new(base(bootstrap: [%{validator: key(1), host: "a b", port: 1}]))

    assert {:error, :bad_bootstrap} =
             Genesis.new(base(bootstrap: [%{validator: key(1), host: "a.b", port: 0}]))
  end

  test "arquivo adulterado ou corrompido é recusado" do
    json = base() |> g!() |> Genesis.to_json()
    tampered = String.replace(json, "\"issuer_threshold\":2", "\"issuer_threshold\":1")
    refute tampered == json
    assert {:error, :hash_mismatch} = Genesis.from_json(tampered)
    assert {:error, :malformed} = Genesis.from_json("nao é json")
    assert {:error, :malformed} = Genesis.from_json("[1,2]")
    assert {:error, _} = Genesis.from_json("{}")
  end

  test "o arquivo não contém segredo e o hash do JSON bate" do
    json = Genesis.to_json(g!())
    refute json =~ "seed"
    assert json =~ Base.encode16(Genesis.hash(g!()), case: :lower)
  end

  test "deriva os parâmetros do ledger e a configuração do canal" do
    g = g!(transfer_base: 1_500, per_byte: 2)
    p = Genesis.ledger_params(g)

    assert p.chain_id == "brdc-devnet" and p.threshold == 2 and p.transfer_base == 1_500 and
             p.per_byte == 2

    assert p.issuers == [key(10), key(11)]
    assert p.contest_window == 86_400 and p.veto_window == 172_800

    withauth = Genesis.ledger_params(g!(authorities: [key(20), key(21)], authority_threshold: 2))
    assert withauth.authorities == [key(20), key(21)] and withauth.authority_threshold == 2
    assert withauth.asset_register_fee == 50_000 and withauth.asset_step_fee == 20_000

    short = Genesis.ledger_params(g!(contest_window: 60, veto_window: 60))
    assert short.contest_window == 60 and short.veto_window == 60

    cfg = Genesis.channel_config(g, key(1))
    assert cfg.genesis_hash == Genesis.hash(g) and cfg.validators.() == g.validators
    assert Genesis.channel_config(g, key(1), fn -> [key(5)] end).validators.() == [key(5)]
  end

  property "lixo nunca levanta exceção ao ler" do
    check all(text <- binary(max_length: 200)) do
      assert match?({:error, _}, Genesis.from_json(text)) or
               match?({:ok, _}, Genesis.from_json(text))
    end
  end
end
