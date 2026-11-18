defmodule BrdcDev.ComposeInitTest do
  use ExUnit.Case, async: true
  alias BrdcDev.Compose
  alias BrdcNode.Genesis

  @moduletag :tmp_dir

  test "init cria chaves, gênese com os nomes dos serviços como pares, compose, .env e lab.json",
       %{tmp_dir: dir} do
    assert {:ok, o} = Compose.init(dir, validators: 4, wallets: 2)
    assert o.validators == 4

    {:ok, g} = dir |> Path.join("net/genesis.json") |> File.read!() |> Genesis.from_json()
    assert g.chain_id == "brdc-lab"
    assert length(g.validators) == 4

    assert Enum.map(g.bootstrap, &{&1.host, &1.port}) == [
             {"v1", 4600},
             {"v2", 4600},
             {"v3", 4600},
             {"v4", 4600}
           ]

    assert Enum.map(g.bootstrap, & &1.validator) == g.validators

    assert File.read!(Compose.compose_file(dir)) =~ "name: brdc-lab"
    assert File.read!(Path.join(dir, ".env")) =~ ~r/^SECRET_KEY_BASE=.{40,}\n/
    assert Compose.read_config(dir) == o

    for r <- ~w(v1 v2 v3 v4 i1 i2 a1 a2),
        do: assert(File.exists?(Path.join(dir, "net/#{r}.seed")))
  end

  test "sementes e .env ficam com permissão 0600", %{tmp_dir: dir} do
    {:ok, _} = Compose.init(dir, validators: 4)

    for f <- ["net/v1.seed", "net/i1.seed", ".env"] do
      {:ok, st} = File.stat(Path.join(dir, f))
      assert Bitwise.band(st.mode, 0o777) == 0o600, "#{f} com permissão aberta"
    end
  end

  test "rodar de novo preserva chaves, gênese e .env, e regenera o compose com as opções novas",
       %{tmp_dir: dir} do
    {:ok, _} = Compose.init(dir, validators: 4, memory: "192m")
    seed = File.read!(Path.join(dir, "net/v2.seed"))
    genesis = File.read!(Path.join(dir, "net/genesis.json"))
    env = File.read!(Path.join(dir, ".env"))

    {:ok, o} = Compose.init(dir, validators: 4, memory: "128m", wallets: 1)
    assert o.memory == "128m"
    assert File.read!(Path.join(dir, "net/v2.seed")) == seed
    assert File.read!(Path.join(dir, "net/genesis.json")) == genesis
    assert File.read!(Path.join(dir, ".env")) == env
    assert File.read!(Compose.compose_file(dir)) =~ "mem_limit: 128m"
  end

  test "outro número de validadores é recusado (outra rede)", %{tmp_dir: dir} do
    {:ok, _} = Compose.init(dir, validators: 4)
    assert {:error, {:validators_mismatch, 4}} = Compose.init(dir, validators: 7)
  end

  test "sem init, read_config é nil", %{tmp_dir: dir} do
    assert Compose.read_config(dir) == nil
  end
end
