// Testes da criptografia do navegador (ADR-0020). Rodam no Node 24 (mesmo `crypto.subtle` do navegador):
//   make js-test
// Os vetores vêm do ELIXIR (vectors/*.json): se o JS divergir, o nó rejeitaria a assinatura.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";

import { sha3_256, tagged } from "./hash.mjs";
import { hex, unhex, utf8, u64, u32, u8, concat, equal } from "./bytes.mjs";
import * as bech32m from "./bech32m.mjs";
import { entropyToMnemonic, mnemonicToEntropy, mnemonicToSeed, isValidMnemonic, randomEntropy } from "./bip39.mjs";
import { derive, master } from "./slip10.mjs";
import { deriveAccount, path, decodeAddress, addressFromPublicKey, verify, keyFromSeed } from "./wallet.mjs";
import { KIND, signingBytes, signTx, encodeTx, txId, transferPayload } from "./tx.mjs";
import { WORDS } from "./bip39_wordlist.mjs";

const load = (name) => JSON.parse(readFileSync(new URL(`../../../../../vectors/${name}`, import.meta.url)));
const crypto = load("crypto.json");
const hashes = load("hash.json");
const txs = load("tx.json");
const ABANDON = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

test("SHA3-256: vetores NIST", () => {
  assert.equal(hex(sha3_256(utf8(""))), "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a");
  assert.equal(hex(sha3_256(utf8("abc"))), "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532");
});

test("SHA3-256 e hash etiquetado: concordam com o Elixir em todos os tamanhos do vetor (bordas de bloco)", () => {
  assert.ok(hashes.cases.length > 100);
  for (const c of hashes.cases) {
    const input = unhex(c.input);
    assert.equal(hex(sha3_256(input)), c.sha3_256, `sha3 len=${c.len}`);
    assert.equal(hex(tagged(hashes.tag, input)), c.tagged, `tagged len=${c.len}`);
  }
});

test("SHA3-256 contra o do Node em 1000 entradas aleatórias", () => {
  for (let i = 0; i < 1000; i++) {
    const m = globalThis.crypto.getRandomValues(new Uint8Array(i % 400));
    assert.equal(hex(sha3_256(m)), createHash("sha3-256").update(m).digest("hex"));
  }
});

test("hash etiquetado separa domínios", () => {
  assert.notEqual(hex(tagged("brdc/tx", utf8("x"))), hex(tagged("brdc/block", utf8("x"))));
  assert.notEqual(hex(tagged("ab", utf8("c"))), hex(tagged("a", utf8("bc"))));
});

test("bech32m: vetores BIP-350 e erros", () => {
  for (const s of ["A1LQFN3A", "a1lqfn3a", "abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx"]) assert.ok(bech32m.decode(s));
  assert.throws(() => bech32m.decode("a1lqfn3p"), /checksum/);
  assert.throws(() => bech32m.decode("A1lqfn3a"), /caixa/);
  assert.throws(() => bech32m.decode("abcdef"), /separador/);
  assert.throws(() => bech32m.decode("1lqfn3a"), /prefixo/);
});

test("bech32m: ida e volta e troca de um caractere é sempre detectada", () => {
  for (let i = 0; i < 200; i++) {
    const bytes = globalThis.crypto.getRandomValues(new Uint8Array(32));
    const text = bech32m.encode("brdc", bytes);
    const back = bech32m.decode(text);
    assert.equal(back.hrp, "brdc");
    assert.ok(equal(back.bytes, bytes));
    const pos = 5 + (i % (text.length - 5));
    const other = text[pos] === "q" ? "p" : "q";
    assert.throws(() => bech32m.decode(text.slice(0, pos) + other + text.slice(pos + 1)));
  }
});

test("BIP-39: vetores oficiais de entropia e de semente", async () => {
  assert.equal(await entropyToMnemonic(new Uint8Array(16)), ABANDON);
  assert.equal(await entropyToMnemonic(new Uint8Array(16).fill(0x7f)), "legal winner thank year wave sausage worth useful legal winner thank yellow");
  assert.equal(await entropyToMnemonic(new Uint8Array(16).fill(0x80)), "letter advice cage absurd amount doctor acoustic avoid letter advice cage above");
  assert.equal(await entropyToMnemonic(new Uint8Array(16).fill(0xff)), "zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo zoo wrong");
  assert.ok(hex(await mnemonicToSeed(ABANDON)).startsWith("5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1"));
  assert.ok(hex(await mnemonicToSeed(ABANDON, "TREZOR")).startsWith("c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"));
});

test("BIP-39: lista, checksum, palavra e tamanho inválidos; ida e volta aleatória", async () => {
  assert.equal(WORDS.length, 2048);
  assert.equal(new Set(WORDS).size, 2048);
  assert.equal(await isValidMnemonic(ABANDON), true);
  assert.equal(await isValidMnemonic(ABANDON.replace("about", "abandon")), false);
  assert.equal(await isValidMnemonic(ABANDON.replace("about", "xyzzy")), false);
  assert.equal(await isValidMnemonic("foo bar"), false);
  for (const bits of [128, 160, 192, 224, 256]) {
    const e = randomEntropy(bits);
    assert.ok(equal(await mnemonicToEntropy(await entropyToMnemonic(e)), e));
  }
});

test("SLIP-10 Ed25519: vetor 1 oficial", async () => {
  const seed = unhex(crypto.slip10.seed);
  const m = await master(seed);
  assert.equal(hex(m.key), "2b4be7f19ee27bbf30c667b642d5f4aa69fd169872f8fc3059c08ebae2eb19e7");
  const n = await derive(seed, "m/0'");
  assert.equal(hex(n.key), crypto.slip10.key);
  assert.equal(hex(n.chain), crypto.slip10.chain_code);
  await assert.rejects(() => derive(seed, "m/0"), /caminho/);
  await assert.rejects(() => derive(seed, "x/0'"), /caminho/);
  await assert.rejects(() => derive(seed, "m/-1'"), /caminho/);
});

test("contas: endereço, chave pública e passphrase concordam com o Elixir", async () => {
  for (const a of crypto.accounts) {
    assert.equal(a.path, path());
    assert.ok(hex(await mnemonicToSeed(crypto.mnemonic, a.passphrase)).startsWith(a.seed_prefix));
    const acc = await deriveAccount(crypto.mnemonic, a.passphrase);
    assert.equal(hex(acc.publicKey), a.public_key);
    assert.equal(acc.address, a.address);
  }
});

test("outra passphrase, conta ou índice dá outro endereço; a mesma dá o mesmo", async () => {
  const a = await deriveAccount(ABANDON);
  const same = await deriveAccount(ABANDON, "");
  const other = await deriveAccount(ABANDON, "segredo");
  const idx = await deriveAccount(ABANDON, "", 0, 1);
  const acct = await deriveAccount(ABANDON, "", 1, 0);
  assert.equal(a.address, same.address);
  assert.equal(new Set([a.address, other.address, idx.address, acct.address]).size, 4);
  await assert.rejects(() => deriveAccount(ABANDON.replace("about", "abandon")), /checksum/);
});

test("a chave de assinatura é NÃO extraível", async () => {
  const seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
  const { publicKey, signingKey } = await keyFromSeed(seed);
  assert.equal(hex(publicKey), "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
  assert.equal(signingKey.extractable, false);
  await assert.rejects(() => globalThis.crypto.subtle.exportKey("pkcs8", signingKey));
  await assert.rejects(() => globalThis.crypto.subtle.exportKey("jwk", signingKey));
});

test("endereço: prefixo, tamanho e checksum", async () => {
  const acc = await deriveAccount(ABANDON);
  assert.ok(acc.address.startsWith("brdc1"));
  assert.equal(decodeAddress(acc.address).length, 32);
  assert.equal(addressFromPublicKey(acc.publicKey), acc.address);
  assert.throws(() => decodeAddress(bech32m.encode("btc", new Uint8Array(32))), /prefixo/);
  assert.throws(() => decodeAddress(bech32m.encode("brdc", new Uint8Array(16))), /tamanho/);
});

test("transações: bytes, assinatura e id IDÊNTICOS aos do Elixir", async () => {
  for (const v of txs.txs) {
    const from = await deriveAccount(txs.mnemonic, v.from_passphrase);
    assert.equal(hex(from.publicKey), v.sender_public_key);
    const tx = {
      chainId: v.chain_id,
      kind: KIND.transfer,
      nonce: v.nonce,
      fee: v.fee,
      senderPublicKey: from.publicKey,
      payload: transferPayload(v.to_address, BigInt(v.amount)),
    };
    assert.equal(hex(tx.payload), v.payload);
    assert.equal(hex(signingBytes(tx)), v.signing_bytes);
    const signed = await signTx(tx, from);
    assert.equal(hex(signed.signature), v.signature);
    assert.equal(hex(encodeTx(signed)), v.encoded);
    assert.equal(hex(txId(signed)), v.txid);
    assert.equal(await verify(tagged("brdc/tx", signingBytes(tx)), signed.signature, from.publicKey), true);
  }
});

test("assinatura só vale para aquela mensagem e chave", async () => {
  const a = await deriveAccount(ABANDON);
  const b = await deriveAccount(ABANDON, "segredo");
  const msg = utf8("oi");
  const sig = await a.sign(msg);
  assert.equal(await verify(msg, sig, a.publicKey), true);
  assert.equal(await verify(utf8("oi!"), sig, a.publicKey), false);
  assert.equal(await verify(msg, sig, b.publicKey), false);
});

test("codificação: inteiros nos limites e tamanhos", () => {
  assert.equal(hex(u64(0xffffffffffffffffn)), "ffffffffffffffff");
  assert.equal(hex(u32(0xffffffff)), "ffffffff");
  assert.equal(hex(u8(255)), "ff");
  assert.throws(() => u64(1n << 64n), RangeError);
  assert.throws(() => u64(-1), RangeError);
  assert.throws(() => u32(2 ** 32), RangeError);
  assert.throws(() => u8(256), RangeError);
  // Number impreciso (acima de 2^53) é recusado; BigInt e texto passam
  assert.throws(() => u64(18446744073709552000), RangeError);
  assert.throws(() => u64(1.5), RangeError);
  assert.equal(hex(u64("18446744073709551615")), "ffffffffffffffff");
  assert.equal(hex(u64(2n ** 63n)), "8000000000000000");
  assert.throws(() => transferPayload((async () => "x")(), 0), Error);
});

test("transferência: valor zero ou negativo é recusado", async () => {
  const acc = await deriveAccount(ABANDON);
  assert.throws(() => transferPayload(acc.address, 0), RangeError);
  assert.throws(() => transferPayload(acc.address, -5), RangeError);
});

test("hex e concat", () => {
  assert.equal(hex(concat(unhex("01"), unhex("0203"))), "010203");
  assert.throws(() => unhex("zz"), /hex/);
  assert.throws(() => unhex("abc"), /hex/);
});
