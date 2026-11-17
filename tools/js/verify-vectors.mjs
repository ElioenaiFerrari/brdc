// Confere os vetores de vectors/crypto.json com JavaScript puro (Node, sem dependências).
// Prova que a lógica que a carteira web vai usar (BIP-39 + SLIP-10 + endereço) dá
// exatamente o mesmo resultado que o Elixir. Na carteira, o navegador usará WebCrypto/
// biblioteca auditada (decisão P6); aqui o Node serve só como referência independente.
import { createHash, createHmac, pbkdf2Sync, createPrivateKey, createPublicKey } from "node:crypto";
import { readFileSync } from "node:fs";

const vectors = JSON.parse(readFileSync(new URL("../../vectors/crypto.json", import.meta.url)));
const hex = (b) => Buffer.from(b).toString("hex");
let failures = 0;
const eq = (name, got, want) => {
  if (got !== want) { failures++; console.error(`FALHOU ${name}\n  obtido:   ${got}\n  esperado: ${want}`); }
  else console.log(`ok  ${name}`);
};

// --- BIP-39: semente = PBKDF2-HMAC-SHA512(frase, "mnemonic"+passphrase, 2048, 64)
const seedOf = (m, p) =>
  pbkdf2Sync(m.normalize("NFKD"), "mnemonic" + p.normalize("NFKD"), 2048, 64, "sha512");

// --- SLIP-10 Ed25519 (só endurecido)
const master = (seed) => {
  const i = createHmac("sha512", "ed25519 seed").update(seed).digest();
  return { key: i.subarray(0, 32), chain: i.subarray(32) };
};
const child = ({ key, chain }, index) => {
  const data = Buffer.alloc(37);
  key.copy(data, 1);
  data.writeUInt32BE((index | 0x80000000) >>> 0, 33);
  const i = createHmac("sha512", chain).update(data).digest();
  return { key: i.subarray(0, 32), chain: i.subarray(32) };
};
const derive = (seed, path) => {
  const parts = path.split("/").slice(1);
  return parts.reduce((n, p) => {
    if (!p.endsWith("'")) throw new Error("só endurecido");
    return child(n, parseInt(p.slice(0, -1), 10));
  }, master(seed));
};

// --- Ed25519: chave pública a partir da semente (PKCS8 fixo + export JWK)
const publicKey = (seed) => {
  const pkcs8 = Buffer.concat([Buffer.from("302e020100300506032b657004220420", "hex"), seed]);
  const jwk = createPublicKey(createPrivateKey({ key: pkcs8, format: "der", type: "pkcs8" })).export({ format: "jwk" });
  return Buffer.from(jwk.x, "base64url");
};

// --- hash etiquetado e bech32m
const tagged = (tag, data) =>
  createHash("sha3-256").update(Buffer.concat([(() => { const b = Buffer.alloc(4); b.writeUInt32BE(Buffer.byteLength(tag)); return b; })(), Buffer.from(tag), data])).digest();

const CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
const GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
const polymod = (values) => {
  let chk = 1;
  for (const v of values) {
    const top = chk >>> 25;
    chk = (((chk & 0x1ffffff) << 5) ^ v) >>> 0;
    for (let i = 0; i < 5; i++) if ((top >>> i) & 1) chk = (chk ^ GEN[i]) >>> 0;
  }
  return chk;
};
const bech32m = (hrp, bytes) => {
  const bits = [...bytes].flatMap((b) => [...Array(8)].map((_, i) => (b >> (7 - i)) & 1));
  while (bits.length % 5) bits.push(0);
  const five = [];
  for (let i = 0; i < bits.length; i += 5) five.push(bits.slice(i, i + 5).reduce((a, b) => a * 2 + b, 0));
  const hrpExp = [...hrp].map((c) => c.charCodeAt(0) >> 5).concat([0], [...hrp].map((c) => c.charCodeAt(0) & 31));
  const pm = (polymod([...hrpExp, ...five, 0, 0, 0, 0, 0, 0]) ^ 0x2bc830a3) >>> 0;
  const check = [...Array(6)].map((_, i) => (pm >>> (5 * (5 - i))) & 31);
  return hrp + "1" + [...five, ...check].map((v) => CHARSET[v]).join("");
};

for (const a of vectors.accounts) {
  const seed = seedOf(vectors.mnemonic, a.passphrase);
  const label = `conta com passphrase ${JSON.stringify(a.passphrase)}`;
  eq(`${label}: semente`, hex(seed).slice(0, 16), a.seed_prefix);
  const pub = publicKey(derive(seed, a.path).key);
  eq(`${label}: chave pública`, hex(pub), a.public_key);
  eq(`${label}: endereço`, bech32m("brdc", tagged("brdc/addr", pub)), a.address);
}
const s = vectors.slip10;
const n = derive(Buffer.from(s.seed, "hex"), s.path);
eq("SLIP-10 chave", hex(n.key), s.key);
eq("SLIP-10 chain code", hex(n.chain), s.chain_code);
const t = vectors.tagged_hash;
eq("hash etiquetado", hex(tagged(t.tag, Buffer.from(t.data_hex, "hex"))), t.hash);

if (failures) { console.error(`${failures} falha(s)`); process.exit(1); }
console.log("JS e Elixir concordam em todos os vetores.");
