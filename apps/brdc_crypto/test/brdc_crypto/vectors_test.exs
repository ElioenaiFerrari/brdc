defmodule BrdcCrypto.VectorsTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Bech32m, Bip39, Ed25519, Hash, Slip10}

  @abandon "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

  defp hex(b), do: Base.encode16(b, case: :lower)
  defp unhex(s), do: Base.decode16!(s, case: :lower)

  test "SHA3-256 de \"ola\" (vetor usado na documentação)" do
    assert String.starts_with?(hex(Hash.sha3("ola")), "f1cd78b7")
    assert String.ends_with?(hex(Hash.sha3("ola")), "241a")
  end

  test "hash etiquetado separa domínios" do
    refute Hash.tagged("brdc/tx", "x") == Hash.tagged("brdc/block", "x")
    refute Hash.tagged("ab", "c") == Hash.tagged("a", "bc")
  end

  describe "BIP-39 (vetores oficiais)" do
    test "entropia zero gera a frase 'abandon … about'" do
      assert Bip39.from_entropy(<<0::128>>) == @abandon
    end

    test "entropia 0x7f… e 0x80… e 0xff…" do
      assert Bip39.from_entropy(String.duplicate(<<0x7F>>, 16)) ==
               "legal winner thank year wave sausage worth useful legal winner thank yellow"

      assert Bip39.from_entropy(String.duplicate(<<0x80>>, 16)) ==
               "letter advice cage absurd amount doctor acoustic avoid letter advice cage above"

      assert Bip39.from_entropy(String.duplicate(<<0xFF>>, 16)) ==
               "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong"
    end

    test "semente sem passphrase e com 'TREZOR'" do
      assert hex(Bip39.to_seed(@abandon)) ==
               "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4"

      assert hex(Bip39.to_seed(@abandon, "TREZOR")) ==
               "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e53495531f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04"
    end

    test "a lista tem 2048 palavras distintas" do
      assert length(Bip39.wordlist()) == 2048
      assert length(Enum.uniq(Bip39.wordlist())) == 2048
    end

    test "recusa checksum errado, palavra desconhecida e tamanho errado" do
      bad = String.replace(@abandon, "about", "abandon")
      assert Bip39.to_entropy(bad) == {:error, :bad_checksum}
      assert Bip39.to_entropy("foo bar") == {:error, :bad_length}

      assert Bip39.to_entropy(String.replace(@abandon, "about", "xyzzy")) ==
               {:error, :unknown_word}
    end
  end

  describe "SLIP-10 Ed25519 (vetor 1 oficial)" do
    @seed Base.decode16!("000102030405060708090a0b0c0d0e0f", case: :lower)

    test "mestre" do
      m = Slip10.master(@seed)
      assert hex(m.key) == "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7"

      assert hex(m.chain_code) ==
               "90046a93de5380a72b5e45010748567d5ea02bbf6522f979e05c0d8d8ca9fffb"

      assert hex(Ed25519.public_key(m.key)) ==
               "a4b2856bfec510abab89753fac1ac0e1112364e7d250545963f135f2a33188ed"
    end

    test "m/0'" do
      {:ok, n} = Slip10.derive(@seed, "m/0'")
      assert hex(n.key) == "68e0fe46dfb67e368c75379acec591dad19df3cde26e63b93a8e704f1dade7a3"

      assert hex(n.chain_code) ==
               "8b59aa11380b624e81507a27fedda59fea6d0b779a778918a2fd3590e16e9c69"
    end

    test "caminho não endurecido ou malformado é recusado" do
      assert Slip10.derive(@seed, "m/0") == {:error, :bad_path}
      assert Slip10.derive(@seed, "x/0'") == {:error, :bad_path}
      assert Slip10.derive(@seed, "m/-1'") == {:error, :bad_path}
    end
  end

  describe "Bech32m (BIP-350)" do
    test "vetores válidos" do
      for s <- ["A1LQFN3A", "a1lqfn3a", "abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx"] do
        assert {:ok, _, _} = Bech32m.decode(s)
      end
    end

    test "vetores inválidos" do
      assert {:error, :bad_checksum} = Bech32m.decode("a1lqfn3p")
      assert {:error, :mixed_case} = Bech32m.decode("A1lqfn3a")
      assert {:error, :no_separator} = Bech32m.decode("abcdef")
      assert {:error, :empty_hrp} = Bech32m.decode("1lqfn3a")
    end
  end

  test "Ed25519: vetor RFC 8032 (mensagem vazia)" do
    seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")

    assert hex(Ed25519.public_key(seed)) ==
             "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"

    sig = Ed25519.sign("", seed)

    assert hex(sig) ==
             "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

    assert Ed25519.verify("", sig, Ed25519.public_key(seed))
    refute Ed25519.verify("x", sig, Ed25519.public_key(seed))
  end
end
