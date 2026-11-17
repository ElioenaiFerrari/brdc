defmodule BrdcNode.KeygenTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.Ed25519
  alias BrdcNode.Keygen

  @moduletag :tmp_dir

  test "gera semente 0600 e chave pública que conferem", %{tmp_dir: dir} do
    assert {:ok, r} = Keygen.generate(dir, "v1")
    assert {:ok, seed} = Keygen.load_seed(r.seed_path)
    assert Ed25519.public_key(seed) == r.public_key
    assert {:ok, r.public_key} == Keygen.load_public(r.pub_path)

    {:ok, stat} = File.stat(r.seed_path)
    assert Bitwise.band(stat.mode, 0o777) == 0o600
  end

  test "nunca sobrescreve uma chave existente", %{tmp_dir: dir} do
    {:ok, r} = Keygen.generate(dir, "v1")
    before = File.read!(r.seed_path)
    assert {:error, :exists} = Keygen.generate(dir, "v1")
    assert File.read!(r.seed_path) == before
  end

  test "duas chaves geradas são diferentes", %{tmp_dir: dir} do
    {:ok, a} = Keygen.generate(dir, "a")
    {:ok, b} = Keygen.generate(dir, "b")
    refute a.public_key == b.public_key
  end

  test "nome inválido é recusado (sem sair da pasta)", %{tmp_dir: dir} do
    for bad <- ["", "../x", "A", "a b", "a/b", String.duplicate("a", 33)] do
      assert {:error, :invalid_name} = Keygen.generate(dir, bad)
    end
  end

  test "semente legível por outros é recusada", %{tmp_dir: dir} do
    {:ok, r} = Keygen.generate(dir, "v1")
    File.chmod!(r.seed_path, 0o644)
    assert {:error, :insecure_permissions} = Keygen.load_seed(r.seed_path)
  end

  test "arquivo malformado e inexistente", %{tmp_dir: dir} do
    path = Path.join(dir, "ruim.seed")
    File.write!(path, "nao-e-hex\n")
    File.chmod!(path, 0o600)
    assert {:error, :malformed} = Keygen.load_seed(path)
    assert {:error, :enoent} = Keygen.load_seed(Path.join(dir, "nao-existe.seed"))
  end

  test "a semente nunca aparece no resultado devolvido", %{tmp_dir: dir} do
    {:ok, r} = Keygen.generate(dir, "v1")
    {:ok, seed} = Keygen.load_seed(r.seed_path)
    refute inspect(r) =~ Base.encode16(seed, case: :lower)
  end
end
