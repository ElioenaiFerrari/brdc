# Gera vectors/hash.json e vectors/tx.json com o ELIXIR como fonte da verdade.
# O JS da carteira (apps/brdc_web/assets/js/crypto) tem de reproduzir exatamente estes bytes.
#   mix run tools/gen_wallet_vectors.exs
alias BrdcCrypto.{Account, Address, Hash}
alias BrdcLedger.Tx

hex = &Base.encode16(&1, case: :lower)

# --- SHA3-256 e hash etiquetado: tamanhos de 0 a 600, com as bordas do bloco de 136 bytes -------
lengths = Enum.to_list(0..140) ++ [199, 200, 201, 270, 271, 272, 273, 274, 407, 408, 409, 410, 599, 600]

input = fn len -> for i <- 0..(len - 1)//1, into: <<>>, do: <<rem(i * 31 + len * 7, 256)>> end

hashes =
  for len <- lengths do
    data = input.(len)
    %{len: len, input: hex.(data), sha3_256: hex.(Hash.sha3(data)), tagged: hex.(Hash.tagged("brdc/test", data))}
  end

File.write!("vectors/hash.json", JSON.encode!(%{tag: "brdc/test", cases: hashes}))

# --- transações de transferência assinadas por contas derivadas da frase de teste ----------------
mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
{:ok, a} = Account.from_mnemonic(mnemonic, "")
{:ok, b} = Account.from_mnemonic(mnemonic, "segredo")

cases = [
  {a, b, 0, 1_000, 1, "brdc-vectors"},
  {a, b, 1, 1_500, 123_456_789, "brdc-vectors"},
  {b, a, 0, 5_000, 1_000_000, "outra-rede"},
  {a, b, 7, 20_000, 0xFFFFFFFFFFFFFFFF, "brdc-vectors"}
]

txs =
  for {from, to, nonce, fee, amount, chain} <- cases do
    {:ok, to_hash} = Address.decode(to.address)
    payload = Tx.transfer_payload(to_hash, amount)

    tx =
      %Tx{chain_id: chain, kind: 1, nonce: nonce, fee: fee, sender_pub: from.public_key, payload: payload}
      |> Tx.sign(from.seed)

    %{
      chain_id: chain,
      kind: 1,
      nonce: nonce,
      fee: fee,
      # texto: o JSON em JavaScript perde precisão acima de 2^53, e valores chegam a 2^64 - 1
      amount: Integer.to_string(amount),
      from_passphrase: if(from == a, do: "", else: "segredo"),
      to_address: to.address,
      sender_public_key: hex.(from.public_key),
      payload: hex.(payload),
      signing_bytes: hex.(Tx.signing_bytes(tx)),
      signature: hex.(tx.signature),
      encoded: hex.(Tx.encode(tx)),
      txid: hex.(Tx.id(tx))
    }
  end

File.write!("vectors/tx.json", JSON.encode!(%{mnemonic: mnemonic, txs: txs}))
IO.puts("vectors/hash.json (#{length(hashes)} casos) e vectors/tx.json (#{length(txs)} transações) gerados")
