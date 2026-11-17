defmodule BrdcCrypto.SharedVectorsTest do
  @moduledoc "Lê vectors/crypto.json, o MESMO arquivo que tools/js/verify-vectors.mjs confere em JS."
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Account, Bip39, Hash, Slip10}

  @path Path.expand("../../../../vectors/crypto.json", __DIR__)
  @external_resource @path
  @vectors @path |> File.read!() |> JSON.decode!()

  defp hex(b), do: Base.encode16(b, case: :lower)

  for a <- @vectors["accounts"] do
    test "conta com passphrase #{inspect(a["passphrase"])} bate com o vetor" do
      a = unquote(Macro.escape(a))
      m = unquote(@vectors["mnemonic"])
      {:ok, acc} = Account.from_mnemonic(m, a["passphrase"])
      assert Account.path() == a["path"]
      assert hex(Bip39.to_seed(m, a["passphrase"])) |> String.starts_with?(a["seed_prefix"])
      assert hex(acc.public_key) == a["public_key"]
      assert acc.address == a["address"]
    end
  end

  test "SLIP-10 e hash etiquetado batem com o vetor" do
    s = @vectors["slip10"]
    {:ok, n} = Slip10.derive(Base.decode16!(s["seed"], case: :lower), s["path"])
    assert hex(n.key) == s["key"]
    assert hex(n.chain_code) == s["chain_code"]
    t = @vectors["tagged_hash"]
    assert hex(Hash.tagged(t["tag"], Base.decode16!(t["data_hex"], case: :lower))) == t["hash"]
  end
end
