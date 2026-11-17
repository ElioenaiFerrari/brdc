// Conta da carteira: frase + passphrase -> chave de assinatura NÃO extraível + endereço brdc1….
import { subtle } from "./subtle.mjs";
import { concat, unhex, fixed } from "./bytes.mjs";
import { mnemonicToSeed, mnemonicToEntropy } from "./bip39.mjs";
import { derive } from "./slip10.mjs";
import { tagged } from "./hash.mjs";
import * as bech32m from "./bech32m.mjs";

/** "BRDC" em ASCII (0x42524443). Não registrado no SLIP-44 (provisório, ADR-0005). */
export const COIN_TYPE = 0x42524443;
export const HRP = "brdc";

export const path = (account = 0, index = 0) => `m/44'/${COIN_TYPE}'/${account}'/0'/${index}'`;

const PKCS8_ED25519 = unhex("302e020100300506032b657004220420");

/** Os 32 bytes de hash que o endereço carrega (é o que o livro-razão guarda). */
export const addressHash = (publicKey) => tagged("brdc/addr", fixed(publicKey, 32));

export const addressFromPublicKey = (publicKey) => bech32m.encode(HRP, addressHash(publicKey));

/** Valida um endereço `brdc1…` e devolve os 32 bytes de hash. */
export function decodeAddress(address) {
  const { hrp, bytes } = bech32m.decode(address);
  if (hrp !== HRP) throw new Error("prefixo errado");
  if (bytes.length !== 32) throw new Error("tamanho errado");
  return bytes;
}

/**
 * Importa a semente de 32 bytes duas vezes: a primeira (extraível, só por um instante) para ler a
 * chave pública; a segunda, definitiva, **não extraível**: depois disso, ninguém lê a chave privada.
 */
export async function keyFromSeed(seed32) {
  const pkcs8 = concat(PKCS8_ED25519, fixed(seed32, 32));
  const temp = await subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, true, ["sign"]);
  const jwk = await subtle.exportKey("jwk", temp);
  const publicKey = Uint8Array.from(atob(jwk.x.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const signingKey = await subtle.importKey("pkcs8", pkcs8, { name: "Ed25519" }, false, ["sign"]);
  pkcs8.fill(0);
  return { publicKey, signingKey };
}

/** Deriva a conta. A frase é validada (checksum); a passphrase não. */
export async function deriveAccount(mnemonic, passphrase = "", account = 0, index = 0) {
  await mnemonicToEntropy(mnemonic);
  const seed = await mnemonicToSeed(mnemonic, passphrase);
  const node = await derive(seed, path(account, index));
  const { publicKey, signingKey } = await keyFromSeed(node.key);
  node.key.fill(0);
  seed.fill(0);
  return {
    publicKey,
    address: addressFromPublicKey(publicKey),
    sign: async (message) => new Uint8Array(await subtle.sign("Ed25519", signingKey, message)),
  };
}

/** Confere uma assinatura Ed25519 (para testes e para a tela de verificação). */
export async function verify(message, signature, publicKey) {
  const key = await subtle.importKey("raw", publicKey, { name: "Ed25519" }, false, ["verify"]);
  return subtle.verify("Ed25519", key, signature, message);
}
