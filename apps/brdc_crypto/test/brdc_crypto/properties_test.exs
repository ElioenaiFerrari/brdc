defmodule BrdcCrypto.PropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.{Account, Address, Bech32m, Bip39, Ed25519, Encoding}

  @abandon "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

  property "bech32m: codificar e decodificar devolve os mesmos bytes" do
    check all(bin <- binary(max_length: 64)) do
      assert {:ok, "brdc", ^bin} = Bech32m.decode(Bech32m.encode("brdc", bin))
    end
  end

  property "bech32m: trocar um caractere é sempre detectado" do
    check all(
            bin <- binary(length: 32),
            pos <- integer(5..60),
            c <- member_of(~c"qpzry9x8gf2tvdw0s3jn54khce6mua7l")
          ) do
      addr = Bech32m.encode("brdc", bin)
      <<pre::binary-size(^pos), old, post::binary>> = addr

      if old != c do
        assert {:error, _} = Bech32m.decode(<<pre::binary, c, post::binary>>)
      end
    end
  end

  property "BIP-39: entropia -> frase -> entropia" do
    check all(len <- member_of([16, 20, 24, 28, 32]), bin <- binary(length: len)) do
      m = Bip39.from_entropy(bin)
      assert {:ok, ^bin} = Bip39.to_entropy(m)
    end
  end

  property "assinatura confere; mensagem ou chave trocada não" do
    check all(seed <- binary(length: 32), msg <- binary(), other <- binary(length: 32)) do
      pub = Ed25519.public_key(seed)
      sig = Ed25519.sign(msg, seed)
      assert Ed25519.verify(msg, sig, pub)
      assert Ed25519.verify(msg <> "x", sig, pub) == false
      if other != seed, do: refute(Ed25519.verify(msg, sig, Ed25519.public_key(other)))
    end
  end

  property "verify nunca levanta exceção, mesmo com lixo" do
    check all(msg <- binary(), sig <- binary(), pub <- binary()) do
      assert is_boolean(Ed25519.verify(msg, sig, pub))
    end
  end

  property "encoding: ida e volta com o mesmo esquema" do
    check all(
            a <- integer(0..0xFF),
            b <- integer(0..0xFFFFFFFF),
            c <- integer(0..0xFFFFFFFFFFFFFFFF),
            d <- binary(),
            e <- string(:printable),
            f <- list_of(integer(0..0xFFFF), max_length: 8)
          ) do
      schema = [:u8, :u32, :u64, :bytes, :string, {:list, :u64}]
      bin = Encoding.encode(schema, [a, b, c, d, e, f])
      assert {:ok, [^a, ^b, ^c, ^d, ^e, ^f]} = Encoding.decode(schema, bin)
    end
  end

  property "encoding: bytes sobrando ou faltando são recusados" do
    check all(d <- binary(min_length: 1)) do
      bin = Encoding.encode([:bytes], [d])
      assert {:error, :malformed} = Encoding.decode([:bytes], bin <> "x")

      assert {:error, :malformed} =
               Encoding.decode([:bytes], binary_part(bin, 0, byte_size(bin) - 1))
    end
  end

  property "encoding: lixo nunca levanta exceção" do
    check all(bin <- binary()) do
      assert match?({:ok, _}, Encoding.decode([:u64, :string, {:list, :bytes}], bin)) or
               Encoding.decode([:u64, :string, {:list, :bytes}], bin) == {:error, :malformed}
    end
  end

  describe "conta e passphrase (a 25ª palavra)" do
    test "passphrase diferente gera conta totalmente diferente; a mesma, a mesma" do
      {:ok, a} = Account.from_mnemonic(@abandon)
      {:ok, a2} = Account.from_mnemonic(@abandon, "")
      {:ok, b} = Account.from_mnemonic(@abandon, "segredo")
      assert a.address == a2.address
      refute a.address == b.address
      refute a.seed == b.seed
    end

    test "contas e índices diferentes dão endereços diferentes" do
      {:ok, a} = Account.from_mnemonic(@abandon, "", 0, 0)
      {:ok, b} = Account.from_mnemonic(@abandon, "", 0, 1)
      {:ok, c} = Account.from_mnemonic(@abandon, "", 1, 0)
      assert length(Enum.uniq([a.address, b.address, c.address])) == 3
    end

    test "endereço tem prefixo brdc1, bate com a chave e a conta assina" do
      {:ok, a} = Account.from_mnemonic(@abandon)
      assert String.starts_with?(a.address, "brdc1")
      assert Address.matches?(a.address, a.public_key)
      assert Ed25519.verify("oi", Account.sign(a, "oi"), a.public_key)
    end

    test "inspect nunca mostra a semente privada" do
      {:ok, a} = Account.from_mnemonic(@abandon)
      refute inspect(a) =~ Base.encode16(a.seed, case: :lower)
      refute inspect(a) =~ Base.encode16(a.seed)
      assert inspect(a) =~ "REDACTED"
    end

    test "frase inválida é recusada" do
      assert {:error, :bad_checksum} =
               Account.from_mnemonic(String.replace(@abandon, "about", "abandon"))
    end

    test "endereço com prefixo ou tamanho errado é recusado" do
      assert {:error, :wrong_prefix} = Address.decode(Bech32m.encode("btc", <<0::256>>))
      assert {:error, :bad_size} = Address.decode(Bech32m.encode("brdc", <<0::128>>))
    end
  end
end
