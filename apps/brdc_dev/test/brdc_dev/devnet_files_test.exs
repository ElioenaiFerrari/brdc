defmodule BrdcDev.DevnetFilesTest do
  # a pasta de uma máquina numa rede entre computadores: gênese existe, mas faltam as sementes dos outros validadores
  use ExUnit.Case, async: true
  alias BrdcDev.Devnet

  @moduletag :tmp_dir

  test "com a gênese criada, ensure NÃO gera sementes que faltam (não bateriam com a gênese)", %{
    tmp_dir: dir
  } do
    {:ok, full} = Devnet.ensure(dir, validators: 2)
    pub_before = File.read!(Path.join(dir, "v2.pub"))
    File.rm!(Path.join(dir, "v2.seed"))

    assert {:ok, d} = Devnet.ensure(dir)
    refute File.exists?(Path.join(dir, "v2.seed"))
    assert File.read!(Path.join(dir, "v2.pub")) == pub_before
    assert d.genesis == full.genesis
    assert Map.has_key?(d.seeds, "v1") and Map.has_key?(d.seeds, "i1")
    refute Map.has_key?(d.seeds, "v2")
  end

  test "seed! devolve a semente que existe e explica o que fazer quando falta", %{tmp_dir: dir} do
    {:ok, _} = Devnet.ensure(dir, validators: 2)
    File.rm!(Path.join(dir, "i2.seed"))
    {:ok, d} = Devnet.ensure(dir)

    assert byte_size(Devnet.seed!(d, "i1")) == 32

    e = assert_raise ArgumentError, fn -> Devnet.seed!(d, "i2") end
    assert e.message =~ "i2.seed"
    assert e.message =~ "nunca é copiada"
  end

  test "sem gênese, ensure cria tudo como antes", %{tmp_dir: dir} do
    assert {:ok, d} = Devnet.ensure(dir, validators: 3)
    assert length(d.genesis.validators) == 3
    assert map_size(d.seeds) == 3 + 4
  end
end
