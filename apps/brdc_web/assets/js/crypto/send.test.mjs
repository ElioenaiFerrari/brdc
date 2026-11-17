// Valores e montagem da transferência no navegador (make js-test). A taxa mínima vem do Elixir.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { parseAmount, formatAmount, formatFull } from "./amount.mjs";
import { buildTransfer, minFee } from "./send.mjs";
import { deriveAccount } from "./wallet.mjs";
import { signTx, encodeTx, KIND, signingBytes, transferPayload } from "./tx.mjs";
import { hex } from "./bytes.mjs";

const txs = JSON.parse(readFileSync(new URL("../../../../../vectors/tx.json", import.meta.url)));
const ABANDON = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

test("valores: vírgula decimal, ponto só como milhar bem posicionado, até 6 casas", () => {
  assert.equal(parseAmount("12,5"), 12_500_000n);
  assert.equal(parseAmount("1.234,56"), 1_234_560_000n);
  assert.equal(parseAmount("1.234.567,5"), 1_234_567_500_000n);
  assert.equal(parseAmount("0,000001"), 1n);
  assert.equal(parseAmount("7"), 7_000_000n);
  assert.equal(parseAmount("  3,25 "), 3_250_000n);
  // "1.5" (um e meio, para quem digita em inglês) NÃO pode virar 15
  for (const bad of ["1.5", "12.34", "1.23", "1..234", ".5", "1.2345", "12.345.6", "", ",", "abc", "1,2,3", "1,1234567", "-1", "1,5x", null, undefined, 5]) {
    assert.equal(parseAmount(bad), null, String(bad));
  }
  assert.equal(parseAmount("18446744073709,551615"), 18446744073709551615n);
  assert.equal(parseAmount("18446744073709,551616"), null);
  assert.equal(parseAmount("99999999999999999999"), null);
});

test("valores: texto trunca e a ida e volta das 6 casas é exata", () => {
  assert.equal(formatAmount(0n), "0,00");
  assert.equal(formatAmount(1n), "0,00");
  assert.equal(formatAmount(999_999n), "0,99");
  assert.equal(formatAmount(12_480_570_000n), "12.480,57");
  assert.equal(formatAmount("12480570000"), "12.480,57");
  assert.equal(formatFull(1n), "0,000001");
  for (const u of [0n, 1n, 999_999n, 1_000_000n, 12_480_570_000n, 18446744073709551615n]) {
    assert.equal(parseAmount(formatFull(u)), u);
  }
});

test("taxa mínima do JS = taxa mínima do Elixir (vetores)", async () => {
  for (const v of txs.txs) {
    const from = await deriveAccount(txs.mnemonic, v.from_passphrase);
    const tx = {
      chainId: v.chain_id,
      kind: KIND.transfer,
      nonce: v.nonce,
      fee: v.fee,
      senderPublicKey: from.publicKey,
      payload: transferPayload(v.to_address, BigInt(v.amount)),
    };
    assert.equal(minFee({ transferBase: 1000, perByte: 1 }, tx), BigInt(v.min_fee));
  }
});

test("montar a transferência: taxa mínima, total e bytes assináveis; a assinatura tem o tamanho da taxa", async () => {
  const me = await deriveAccount(ABANDON);
  const other = await deriveAccount(ABANDON, "segredo");
  const info = { chainId: "brdc-devnet", nonce: "3", transferBase: "1000", perByte: "1" };
  const { tx, fee, total } = buildTransfer({ info, senderPublicKey: me.publicKey, toAddress: other.address, amount: 2_500_000n });

  assert.equal(tx.nonce, 3n);
  assert.equal(tx.fee, fee);
  assert.equal(total, 2_500_000n + fee);
  // o tamanho que vai pela rede é o do corpo + 64 de assinatura: a taxa mínima cobre exatamente isso
  const signed = await signTx(tx, me);
  assert.equal(encodeTx(signed).length, signingBytes(tx).length + 64);
  assert.equal(fee, 1000n + BigInt(encodeTx(signed).length));
  assert.equal(hex(signed.signature).length, 128);
});

test("montar a transferência: valor zero, negativo ou endereço inválido são recusados", async () => {
  const me = await deriveAccount(ABANDON);
  const info = { chainId: "x", nonce: "0", transferBase: "1000", perByte: "1" };
  assert.throws(() => buildTransfer({ info, senderPublicKey: me.publicKey, toAddress: me.address, amount: 0n }), RangeError);
  assert.throws(() => buildTransfer({ info, senderPublicKey: me.publicKey, toAddress: "brdc1invalido", amount: 1n }));
});
