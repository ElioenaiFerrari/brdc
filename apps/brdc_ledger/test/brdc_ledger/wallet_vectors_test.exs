defmodule BrdcLedger.WalletVectorsTest do
  @moduledoc """
  Lê vectors/tx.json: transações de transferência assinadas pelo Elixir e **reproduzidas byte a byte**
  pelo JS da carteira (apps/brdc_web/assets/js/crypto). Como o Ed25519 é determinístico, "o JS produz os
  mesmos bytes" prova que o nó aceita o que a carteira assina.
  """
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Account, Address}
  alias BrdcLedger.Tx

  @path Path.expand("../../../../vectors/tx.json", __DIR__)
  @external_resource @path
  @vectors @path |> File.read!() |> JSON.decode!()

  defp hex(b), do: Base.encode16(b, case: :lower)
  defp unhex(s), do: Base.decode16!(s, case: :lower)

  test "o vetor tem casos, inclusive o valor máximo de 64 bits" do
    assert length(@vectors["txs"]) >= 4
    assert Enum.any?(@vectors["txs"], &(&1["amount"] == "18446744073709551615"))
  end

  for {v, i} <- Enum.with_index(@vectors["txs"]) do
    test "transação #{i}: o Elixir ainda produz exatamente os bytes do vetor e os decodifica" do
      v = unquote(Macro.escape(v))
      {:ok, from} = Account.from_mnemonic(@vectors["mnemonic"], v["from_passphrase"])
      {:ok, to_hash} = Address.decode(v["to_address"])
      payload = Tx.transfer_payload(to_hash, String.to_integer(v["amount"]))

      tx =
        %Tx{
          chain_id: v["chain_id"],
          kind: v["kind"],
          nonce: v["nonce"],
          fee: v["fee"],
          sender_pub: from.public_key,
          payload: payload
        }
        |> Tx.sign(from.seed)

      assert hex(from.public_key) == v["sender_public_key"]
      assert hex(payload) == v["payload"]
      assert hex(Tx.signing_bytes(tx)) == v["signing_bytes"]
      assert hex(tx.signature) == v["signature"]
      assert hex(Tx.encode(tx)) == v["encoded"]
      assert hex(Tx.id(tx)) == v["txid"]

      # o que a carteira enviaria chega ao nó assim: decodifica e a assinatura confere
      assert {:ok, decoded} = Tx.decode(unhex(v["encoded"]))
      assert Tx.valid_signature?(decoded)
      assert decoded == tx
    end
  end
end
