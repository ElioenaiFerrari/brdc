// SLIP-0010 para Ed25519: só derivação endurecida. HMAC-SHA512 do WebCrypto.
import { subtle } from "./subtle.mjs";
import { concat, u32, utf8 } from "./bytes.mjs";

async function hmac512(keyBytes, data) {
  const key = await subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  return new Uint8Array(await subtle.sign("HMAC", key, data));
}

const HARDENED = 0x80000000;

export async function master(seed) {
  const i = await hmac512(utf8("ed25519 seed"), seed);
  return { key: i.slice(0, 32), chain: i.slice(32) };
}

export async function child({ key, chain }, index) {
  if (!Number.isInteger(index) || index < 0 || index >= HARDENED) throw new RangeError("índice inválido");
  const data = concat(new Uint8Array([0]), key, u32((index | HARDENED) >>> 0));
  const i = await hmac512(chain, data);
  return { key: i.slice(0, 32), chain: i.slice(32) };
}

/** `path` como `m/44'/0'/0'`: todos os índices precisam ser endurecidos (`'`). */
export async function derive(seed, path) {
  if (path !== "m" && !/^m(\/\d+')+$/.test(path)) throw new Error("caminho inválido");
  let node = await master(seed);
  if (path === "m") return node;
  for (const part of path.split("/").slice(1)) node = await child(node, parseInt(part.slice(0, -1), 10));
  return node;
}
