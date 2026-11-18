defmodule BrdcDev.WalletsTest do
  use ExUnit.Case, async: true
  alias BrdcDev.Wallets

  @moduletag :tmp_dir

  test "cria, lê de volta a mesma conta e lista em ordem", %{tmp_dir: dir} do
    {:ok, a} = Wallets.create(dir, "alice")
    {:ok, _} = Wallets.create(dir, "bob")
    assert Wallets.names(dir) == ["alice", "bob"]
    assert {:ok, again} = Wallets.load(dir, "alice")
    assert again.account.address == a.account.address
    assert again.mnemonic == a.mnemonic
    assert a.account.address =~ ~r/\Abrdc1/
    assert length(String.split(a.mnemonic)) == 12
  end

  test "carteiras diferentes têm endereços diferentes; repetir o nome é recusado; ensure é idempotente",
       %{tmp_dir: dir} do
    {:ok, a} = Wallets.create(dir, "alice")
    {:ok, b} = Wallets.create(dir, "bob")
    refute a.account.address == b.account.address
    assert {:error, :exists} = Wallets.create(dir, "alice")
    {:ok, e1} = Wallets.ensure(dir, "carol")
    {:ok, e2} = Wallets.ensure(dir, "carol")
    assert e1.account.address == e2.account.address
  end

  test "nomes inválidos são recusados (nada de caminho nem maiúsculas)", %{tmp_dir: dir} do
    for bad <- [
          "",
          "A",
          "../x",
          "a/b",
          "a b",
          "-a",
          String.duplicate("a", 33),
          "alice.json",
          nil,
          5
        ] do
      assert {:error, :bad_name} = Wallets.create(dir, bad)
    end

    assert Wallets.valid_name?("a-b_c1")
    refute File.exists?(Path.join(dir, "x.json"))
  end

  test "carteira inexistente ou arquivo corrompido não passam", %{tmp_dir: dir} do
    assert {:error, :not_found} = Wallets.load(dir, "ninguem")
    File.mkdir_p!(Wallets.dir(dir))
    File.write!(Path.join(Wallets.dir(dir), "ruim.json"), "lixo")
    assert {:error, :corrupt} = Wallets.load(dir, "ruim")

    File.write!(
      Path.join(Wallets.dir(dir), "ruim2.json"),
      ~s({"mnemonic": "palavras que nao sao validas"})
    )

    assert {:error, :corrupt} = Wallets.load(dir, "ruim2")
  end

  test "resolve: nome vira carteira com chave; endereço vira só o hash; lixo é erro", %{
    tmp_dir: dir
  } do
    {:ok, a} = Wallets.create(dir, "alice")
    assert {:wallet, w} = Wallets.resolve(dir, "alice")
    assert w.account.address == a.account.address
    assert {:address, hash} = Wallets.resolve(dir, a.account.address)
    assert hash == Wallets.hash({:wallet, w})
    assert {:error, {:bad_address, _}} = Wallets.resolve(dir, "brdc1invalido")
    assert {:error, :not_found} = Wallets.resolve(dir, "ninguem")
  end
end
