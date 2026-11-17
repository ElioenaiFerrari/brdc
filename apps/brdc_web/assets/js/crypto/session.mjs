// Sessão da carteira: cria, importa, destrava e bloqueia. A conta destravada vive SÓ aqui, em memória, e
// some ao bloquear ou depois de um tempo sem uso. Nada daqui sai para o servidor além do endereço.
import { entropyToMnemonic, isValidMnemonic, randomEntropy } from "./bip39.mjs";
import { deriveAccount } from "./wallet.mjs";
import { createVault, unlockVault, VaultError, DEFAULT_ITERATIONS } from "./vault.mjs";

export const DEFAULT_IDLE_MS = 5 * 60 * 1000;

/**
 * `store`: memoryStore() ou indexedDbStore(). `iterations`: voltas do KDF (testes usam menos).
 * `timers`: { setTimeout, clearTimeout } injetáveis para testar o bloqueio por inatividade.
 */
export function createSession({
  store,
  iterations = DEFAULT_ITERATIONS,
  idleMs = DEFAULT_IDLE_MS,
  timers = { setTimeout: globalThis.setTimeout.bind(globalThis), clearTimeout: globalThis.clearTimeout.bind(globalThis) },
  onLock = () => {},
} = {}) {
  let account = null; // { publicKey, address, sign }
  let timer = null;

  const arm = () => {
    if (timer !== null) timers.clearTimeout(timer);
    timer = timers.setTimeout(lock, idleMs);
  };

  function lock() {
    if (timer !== null) timers.clearTimeout(timer);
    timer = null;
    const was = account !== null;
    account = null;
    if (was) onLock();
  }

  async function open(secret, mnemonic, passphrase) {
    const acc = await deriveAccount(mnemonic, passphrase);
    account = acc;
    arm();
    return { address: acc.address, matchesVault: secret ? secret.address === acc.address : true };
  }

  return {
    /** "none": sem cofre · "locked": cofre fechado · "unlocked": conta na memória. */
    async status() {
      if (account) return "unlocked";
      return (await store.get()) ? "locked" : "none";
    },

    /** Frase nova (24 palavras). Só existe na memória de quem chamou até `create`. */
    async newMnemonic() {
      return entropyToMnemonic(randomEntropy(256));
    },

    /** Cria o cofre com a frase, a passphrase (opcional, NÃO guardada) e a senha local. */
    async create({ mnemonic, passphrase = "", password }) {
      if (!(await isValidMnemonic(mnemonic))) throw new VaultError("frase inválida");
      const acc = await deriveAccount(mnemonic, passphrase);
      const rec = await createVault({ mnemonic, address: acc.address, hasPassphrase: passphrase !== "" }, password, { iterations });
      await store.put(rec);
      account = acc;
      arm();
      return { address: acc.address };
    },

    /**
     * Destrava com a senha local e a passphrase (digitada agora; se vazia, é a carteira sem passphrase).
     * `matchesVault` = false avisa que a passphrase digitada abre OUTRA carteira (não a do cofre).
     */
    async unlock({ password, passphrase = "" }) {
      const rec = await store.get();
      if (!rec) throw new VaultError("não há carteira neste navegador");
      const secret = await unlockVault(rec, password, { minIterations: Math.min(iterations, DEFAULT_ITERATIONS) });
      return open(secret, secret.mnemonic, passphrase);
    },

    /** Conta atual (só destravada). `sign` é o único jeito de usar a chave. */
    account() {
      if (!account) throw new VaultError("carteira bloqueada");
      arm(); // qualquer uso conta como atividade
      return account;
    },

    /** Marca atividade (cliques, teclas) para adiar o bloqueio. */
    touch() {
      if (account) arm();
    },

    lock,

    /** Apaga o cofre deste navegador (a frase continua valendo em qualquer outro lugar). */
    async erase() {
      lock();
      await store.clear();
    },

    /** Cópia do cofre cifrado (texto hexadecimal) para backup. Não contém segredo em claro. */
    async exportVault() {
      return store.get();
    },
  };
}
