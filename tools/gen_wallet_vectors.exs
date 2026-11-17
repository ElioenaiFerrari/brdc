# Gera vectors/hash.json e vectors/tx.json com o ELIXIR como fonte da verdade.
# O JS da carteira (apps/brdc_web/assets/js/crypto) tem de reproduzir exatamente estes bytes.
#   mix run --no-start tools/gen_wallet_vectors.exs
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

{:ok, params} = BrdcLedger.Params.new(chain_id: "x", issuers: [a.public_key], threshold: 1)

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
      txid: hex.(Tx.id(tx)),
      # taxa mínima (ADR-0014) com a tabela padrão: 1000 + 1 por byte do que vai pela rede
      min_fee: Integer.to_string(BrdcLedger.Executor.min_fee(params, tx))
    }
  end

# --- contratos entre partes: criar (tipo 20) e agir (tipo 21), mais os modelos como dado para a carteira ---
{:ok, b_hash} = Address.decode(b.address)

contract_cases = [
  {:create, "compra-venda", "cv-1", [1_000_000, 3_600]},
  {:create, "aluguel", "al-1", [100_000, 2_592_000, 12, 200_000, 86_400]},
  {:create, "emprestimo", "em-1", [1_000_000, 1_100_000, 604_800]},
  {:act, "cv-1", "accept"},
  {:act, "al-1", "pay_rent"}
]

contract_txs =
  for {c, nonce} <- Enum.with_index(contract_cases) do
    {kind, payload, input} =
      case c do
        {:create, template, id, terms} ->
          {20, BrdcLedger.Contracts.create_payload(template, id, b_hash, terms),
           %{template: template, id: id, party_b: b.address, terms: Enum.map(terms, &Integer.to_string/1)}}

        {:act, id, action} ->
          {21, BrdcLedger.Contracts.act_payload(id, action), %{id: id, action: action}}
      end

    tx =
      %Tx{chain_id: "brdc-vectors", kind: kind, nonce: nonce, fee: 10_000, sender_pub: a.public_key, payload: payload}
      |> Tx.sign(a.seed)

    %{
      kind: kind,
      nonce: nonce,
      fee: 10_000,
      input: input,
      payload: hex.(payload),
      signing_bytes: hex.(Tx.signing_bytes(tx)),
      signature: hex.(tx.signature),
      encoded: hex.(Tx.encode(tx)),
      txid: hex.(Tx.id(tx))
    }
  end

# --- assinatura coletiva: documento de emissão de credencial, aprovações de dois membros e a carga final ---
{:ok, m1} = Account.from_mnemonic(mnemonic, "m1")
{:ok, m2} = Account.from_mnemonic(mnemonic, "m2")
{:ok, holder_hash} = Address.decode(b.address)

issue_inputs = [
  %{type: "cnh", id: "cnh-1", data_hex: hex.("categoria=B"), ref: ""},
  %{type: "casamento", id: "cas-a", data_hex: hex.(:crypto.hash(:sha256, "a+b")), ref: ""},
  %{type: "divorcio", id: "div-a", data_hex: hex.(:crypto.hash(:sha256, "a-b")), ref: "cas-a"}
]

issues =
  for i <- issue_inputs do
    data = Base.decode16!(i.data_hex, case: :lower)
    doc = BrdcLedger.Credentials.issue_doc("brdc-vectors", i.type, i.id, holder_hash, data, i.ref)
    approvals = for m <- [m1, m2], do: BrdcLedger.Approvals.approval(doc, m.seed)

    Map.merge(i, %{
      subject: b.address,
      doc: hex.(doc),
      member_public_keys: [hex.(m1.public_key), hex.(m2.public_key)],
      approvals: Enum.map(approvals, hex),
      payload: hex.(BrdcLedger.Credentials.issue_payload(i.type, i.id, holder_hash, data, i.ref, approvals))
    })
  end

File.write!(
  "vectors/tx.json",
  JSON.encode!(%{
    mnemonic: mnemonic,
    txs: txs,
    contract_txs: contract_txs,
    issues: issues,
    chain_id: "brdc-vectors"
  })
)

File.mkdir_p!("apps/brdc_web/assets/js/generated")

File.write!(
  "apps/brdc_web/assets/js/generated/contract_templates.json",
  JSON.encode!(BrdcLedger.ContractTemplates.export()) <> "\n"
)
IO.puts("vectors/hash.json (#{length(hashes)} casos) e vectors/tx.json (#{length(txs)} transações) gerados")
