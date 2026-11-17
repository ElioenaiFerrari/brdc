// Cofre cifrado da carteira (ADR-0006, ADR-0020, ADR-0021).
//
// Guarda a FRASE de 24 palavras cifrada pela SENHA LOCAL. A PASSPHRASE (25ª palavra) NUNCA é guardada
// (ADR-0021): é digitada a cada destravamento. Dentro do cofre cifrado vai também o endereço de quando a
// carteira foi criada, só para avisar se a passphrase digitada agora abre OUTRA carteira.
//
// Cifra: AES-256-GCM. Chave: PBKDF2-HMAC-SHA256 da senha, com sal aleatório. Os parâmetros entram como
// dado autenticado (AAD): adulterar o sal, as voltas ou a versão faz a abertura falhar.
import { subtle, getRandomValues } from "./subtle.mjs";
import { concat, fromUtf8, hex, unhex, utf8 } from "./bytes.mjs";

export const VAULT_VERSION = 1;
/** Piso da OWASP para PBKDF2-HMAC-SHA256. */
export const DEFAULT_ITERATIONS = 600_000;
const MAX_ITERATIONS = 5_000_000;
const SALT_BYTES = 16;
const IV_BYTES = 12;
const TAG_BYTES = 16;

export class VaultError extends Error {
  constructor(message) {
    super(message);
    this.name = "VaultError";
  }
}

/** Motivos pelos quais a senha local não serve (vazio = ok). Texto pensado para a tela. */
export function passwordProblems(password) {
  const problems = [];
  if (typeof password !== "string" || password.length < 12) problems.push("use pelo menos 12 caracteres");
  if (/^(.)\1+$/.test(password ?? "")) problems.push("não repita o mesmo caractere");
  if (/^\d+$/.test(password ?? "")) problems.push("misture letras ou símbolos, não só números");
  return problems;
}

// Dado autenticado: tudo o que não é segredo mas não pode ser trocado.
const aadOf = (rec) =>
  utf8(JSON.stringify(["brdc-vault", rec.v, rec.kdf.name, rec.kdf.iterations, rec.kdf.salt, rec.iv]));

async function deriveKey(password, saltBytes, iterations) {
  const base = await subtle.importKey("raw", utf8(password.normalize("NFKC")), "PBKDF2", false, ["deriveKey"]);
  return subtle.deriveKey(
    { name: "PBKDF2", hash: "SHA-256", salt: saltBytes, iterations },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

/**
 * Cria o registro do cofre. `secret` = { mnemonic, address, hasPassphrase }.
 * Devolve um objeto simples (texto hexadecimal), seguro de guardar e de exportar como backup.
 */
export async function createVault(secret, password, { iterations = DEFAULT_ITERATIONS } = {}) {
  const problems = passwordProblems(password);
  if (problems.length) throw new VaultError(`senha fraca: ${problems.join("; ")}`);
  const salt = getRandomValues(new Uint8Array(SALT_BYTES));
  const iv = getRandomValues(new Uint8Array(IV_BYTES));
  const rec = { v: VAULT_VERSION, kdf: { name: "PBKDF2-SHA256", iterations, salt: hex(salt) }, iv: hex(iv), data: "" };
  const key = await deriveKey(password, salt, iterations);
  const plain = utf8(
    JSON.stringify({ mnemonic: secret.mnemonic, address: secret.address, hasPassphrase: !!secret.hasPassphrase }),
  );
  const cipher = await subtle.encrypt({ name: "AES-GCM", iv, additionalData: aadOf(rec) }, key, plain);
  plain.fill(0);
  return { ...rec, data: hex(new Uint8Array(cipher)) };
}

function validShape(rec, minIterations) {
  const hexOf = (s, bytes) => typeof s === "string" && s.length === bytes * 2 && /^[0-9a-f]+$/.test(s);
  if (!rec || typeof rec !== "object") throw new VaultError("cofre inválido");
  if (rec.v !== VAULT_VERSION) throw new VaultError("versão de cofre desconhecida");
  if (rec.kdf?.name !== "PBKDF2-SHA256") throw new VaultError("KDF desconhecido");
  const n = rec.kdf.iterations;
  if (!Number.isInteger(n) || n < minIterations) throw new VaultError("cofre com poucas voltas de KDF: recusado");
  if (n > MAX_ITERATIONS) throw new VaultError("cofre com voltas de KDF absurdas: recusado");
  if (!hexOf(rec.kdf.salt, SALT_BYTES) || !hexOf(rec.iv, IV_BYTES)) throw new VaultError("cofre inválido");
  if (typeof rec.data !== "string" || !/^([0-9a-f]{2}){17,}$/.test(rec.data)) throw new VaultError("cofre inválido");
}

/**
 * Abre o cofre. Lança `VaultError` se a senha estiver errada **ou** o cofre tiver sido adulterado (o
 * AES-GCM não diferencia, de propósito). `minIterations` recusa cofres rebaixados (padrão: 600 mil).
 */
export async function unlockVault(rec, password, { minIterations = DEFAULT_ITERATIONS } = {}) {
  validShape(rec, minIterations);
  const key = await deriveKey(password, unhex(rec.kdf.salt), rec.kdf.iterations);
  let plain;
  try {
    plain = new Uint8Array(
      await subtle.decrypt({ name: "AES-GCM", iv: unhex(rec.iv), additionalData: aadOf(rec) }, key, unhex(rec.data)),
    );
  } catch {
    throw new VaultError("senha incorreta ou cofre adulterado");
  }
  try {
    const s = JSON.parse(fromUtf8(plain));
    if (typeof s.mnemonic !== "string" || typeof s.address !== "string") throw new Error();
    return { mnemonic: s.mnemonic, address: s.address, hasPassphrase: !!s.hasPassphrase };
  } catch {
    throw new VaultError("conteúdo do cofre inválido");
  } finally {
    plain.fill(0);
  }
}

export { TAG_BYTES, concat };
