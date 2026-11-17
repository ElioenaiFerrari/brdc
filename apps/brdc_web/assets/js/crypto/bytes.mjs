// Utilitários de bytes e a codificação determinística da BRDC (ADR-0011), igual à do Elixir.
const enc = new TextEncoder();
const dec = new TextDecoder("utf-8", { fatal: true });

export const utf8 = (s) => enc.encode(s);
export const fromUtf8 = (b) => dec.decode(b);

export function hex(bytes) {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function unhex(text) {
  if (!/^([0-9a-fA-F]{2})*$/.test(text)) throw new Error("hex inválido");
  const out = new Uint8Array(text.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(text.slice(i * 2, i * 2 + 2), 16);
  return out;
}

export function concat(...parts) {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

export function equal(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

const MAX_U64 = (1n << 64n) - 1n;

function uint(value, bytes, max) {
  // Number acima de 2^53 já perdeu precisão antes de chegar aqui: recusa em vez de arredondar em silêncio.
  if (typeof value === "number" && !Number.isSafeInteger(value)) throw new RangeError("use BigInt ou texto para valores grandes");
  const n = BigInt(value);
  if (n < 0n || n > max) throw new RangeError("inteiro fora do limite");
  const out = new Uint8Array(bytes);
  for (let i = bytes - 1, v = n; i >= 0; i--, v >>= 8n) out[i] = Number(v & 0xffn);
  return out;
}

export const u8 = (v) => uint(v, 1, 0xffn);
export const u32 = (v) => uint(v, 4, 0xffffffffn);
export const u64 = (v) => uint(v, 8, MAX_U64);

/** `bytes`: tamanho (4 bytes) + conteúdo. */
export const bytesField = (b) => concat(u32(b.length), b);

/** `string`: igual a `bytes`, em UTF-8. */
export const stringField = (s) => bytesField(utf8(s));

/** `{:fixed, n}`: exatamente n bytes, sem prefixo. */
export function fixed(b, n) {
  if (b.length !== n) throw new RangeError(`esperava ${n} bytes, recebi ${b.length}`);
  return b;
}
