// BIP-39: frase mnemônica <-> entropia <-> semente (PBKDF2-HMAC-SHA512, com passphrase opcional).
import { WORDS } from "./bip39_wordlist.mjs";
import { subtle, getRandomValues } from "./subtle.mjs";
import { utf8 } from "./bytes.mjs";

const INDEX = new Map(WORDS.map((w, i) => [w, i]));
const norm = (s) => s.normalize("NFKD");

async function sha256(bytes) {
  return new Uint8Array(await subtle.digest("SHA-256", bytes));
}

/** Entropia aleatória (128, 160, 192, 224 ou 256 bits). */
export function randomEntropy(bits = 256) {
  if (![128, 160, 192, 224, 256].includes(bits)) throw new RangeError("tamanho de entropia inválido");
  return getRandomValues(new Uint8Array(bits / 8));
}

/** Entropia (16/20/24/28/32 bytes) -> frase. */
export async function entropyToMnemonic(entropy) {
  if (![16, 20, 24, 28, 32].includes(entropy.length)) throw new RangeError("tamanho de entropia inválido");
  const csBits = entropy.length / 4; // ENT/32
  const hash = await sha256(entropy);
  const bits = [];
  for (const b of entropy) for (let i = 7; i >= 0; i--) bits.push((b >> i) & 1);
  for (let i = 0; i < csBits; i++) bits.push((hash[i >> 3] >> (7 - (i & 7))) & 1);
  const words = [];
  for (let i = 0; i < bits.length; i += 11) words.push(WORDS[bits.slice(i, i + 11).reduce((a, b) => a * 2 + b, 0)]);
  return words.join(" ");
}

/** Confere tamanho, palavras e checksum. Devolve a entropia ou lança erro com o motivo. */
export async function mnemonicToEntropy(mnemonic) {
  const words = norm(mnemonic).trim().split(/\s+/).filter(Boolean);
  if (![12, 15, 18, 21, 24].includes(words.length)) throw new Error("tamanho inválido");
  const bits = [];
  for (const w of words) {
    const i = INDEX.get(w);
    if (i === undefined) throw new Error("palavra desconhecida");
    for (let b = 10; b >= 0; b--) bits.push((i >> b) & 1);
  }
  const csBits = bits.length / 33;
  const entBits = bits.length - csBits;
  const entropy = new Uint8Array(entBits / 8);
  for (let i = 0; i < entropy.length; i++) entropy[i] = bits.slice(i * 8, i * 8 + 8).reduce((a, b) => a * 2 + b, 0);
  const hash = await sha256(entropy);
  for (let i = 0; i < csBits; i++) {
    if (((hash[i >> 3] >> (7 - (i & 7))) & 1) !== bits[entBits + i]) throw new Error("checksum inválido");
  }
  return entropy;
}

export async function isValidMnemonic(mnemonic) {
  try {
    await mnemonicToEntropy(mnemonic);
    return true;
  } catch {
    return false;
  }
}

/** Semente de 64 bytes. A passphrase (25ª palavra) não é validada: qualquer uma abre uma carteira. */
export async function mnemonicToSeed(mnemonic, passphrase = "") {
  const key = await subtle.importKey("raw", utf8(norm(mnemonic).trim()), "PBKDF2", false, ["deriveBits"]);
  const bits = await subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-512", salt: utf8("mnemonic" + norm(passphrase)), iterations: 2048 },
    key,
    512,
  );
  return new Uint8Array(bits);
}
