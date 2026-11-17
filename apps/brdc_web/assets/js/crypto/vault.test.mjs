// Testes do cofre, do armazenamento e da sessão (make js-test). Usa poucas voltas de KDF para ser rápido;
// o padrão de produção (600 mil) tem seu próprio teste.
import test from "node:test";
import assert from "node:assert/strict";
import { createVault, unlockVault, passwordProblems, VaultError, DEFAULT_ITERATIONS } from "./vault.mjs";
import { memoryStore } from "./store.mjs";
import { createSession } from "./session.mjs";
import { hex, unhex } from "./bytes.mjs";

const ABANDON = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
const PW = "uma senha bem longa 2026";
const FAST = { iterations: 1000 };
const OPEN_FAST = { minIterations: 1000 };
const secret = { mnemonic: ABANDON, address: "brdc1teste", hasPassphrase: true };

test("senha local: o mínimo exigido", () => {
  assert.deepEqual(passwordProblems(PW), []);
  assert.ok(passwordProblems("curta").length > 0);
  assert.ok(passwordProblems("aaaaaaaaaaaaaaaa").length > 0);
  assert.ok(passwordProblems("123456789012345").length > 0);
  assert.ok(passwordProblems(undefined).length > 0);
});

test("o padrão de produção são 600 mil voltas de PBKDF2", async () => {
  assert.equal(DEFAULT_ITERATIONS, 600_000);
  const rec = await createVault(secret, PW);
  assert.equal(rec.kdf.iterations, 600_000);
  assert.deepEqual(await unlockVault(rec, PW), secret);
});

test("cria e abre; o registro só tem texto hexadecimal e não deixa a frase à vista", async () => {
  const rec = await createVault(secret, PW, FAST);
  assert.equal(rec.v, 1);
  assert.match(rec.data, /^[0-9a-f]+$/);
  const dump = JSON.stringify(rec);
  assert.ok(!dump.includes("abandon") && !dump.includes("brdc1teste") && !dump.includes(PW));
  assert.deepEqual(await unlockVault(rec, PW, OPEN_FAST), secret);
});

test("senha errada é recusada; dois cofres iguais têm sal, IV e cifra diferentes", async () => {
  const a = await createVault(secret, PW, FAST);
  const b = await createVault(secret, PW, FAST);
  assert.notEqual(a.kdf.salt, b.kdf.salt);
  assert.notEqual(a.iv, b.iv);
  assert.notEqual(a.data, b.data);
  await assert.rejects(() => unlockVault(a, "outra senha qualquer 1", OPEN_FAST), VaultError);
});

test("senha fraca é recusada na criação", async () => {
  await assert.rejects(() => createVault(secret, "curta", FAST), /senha fraca/);
});

test("adulterar qualquer parte do cofre faz a abertura falhar", async () => {
  const rec = await createVault(secret, PW, FAST);
  const flip = (h, i = 0) => {
    const b = unhex(h);
    b[i] ^= 1;
    return hex(b);
  };
  const tampered = [
    { ...rec, data: flip(rec.data) },
    { ...rec, data: flip(rec.data, 5) },
    { ...rec, iv: flip(rec.iv) },
    { ...rec, kdf: { ...rec.kdf, salt: flip(rec.kdf.salt) } },
    { ...rec, kdf: { ...rec.kdf, iterations: rec.kdf.iterations + 1 } },
  ];
  for (const t of tampered) await assert.rejects(() => unlockVault(t, PW, OPEN_FAST), VaultError);
});

test("cofre rebaixado ou malformado é recusado antes de gastar CPU", async () => {
  const rec = await createVault(secret, PW, FAST);
  await assert.rejects(() => unlockVault(rec, PW), /poucas voltas/); // padrão exige 600 mil
  await assert.rejects(() => unlockVault({ ...rec, kdf: { ...rec.kdf, iterations: 10 ** 12 } }, PW, OPEN_FAST), /absurdas/);
  for (const bad of [null, {}, { ...rec, v: 2 }, { ...rec, kdf: { ...rec.kdf, name: "MD5" } }, { ...rec, iv: "00" }, { ...rec, data: "zz" }, { ...rec, data: "00" }]) {
    await assert.rejects(() => unlockVault(bad, PW, OPEN_FAST), VaultError);
  }
});

test("armazenamento em memória copia (não guarda referência)", async () => {
  const s = memoryStore();
  assert.equal(await s.get(), null);
  const rec = { a: 1 };
  await s.put(rec);
  rec.a = 2;
  assert.deepEqual(await s.get(), { a: 1 });
  await s.clear();
  assert.equal(await s.get(), null);
});

function fakeTimers() {
  const pending = new Map();
  let id = 0;
  return {
    setTimeout: (fn, ms) => (pending.set(++id, { fn, ms }), id),
    clearTimeout: (i) => pending.delete(i),
    fire: () => {
      const [i, t] = [...pending.entries()].pop() ?? [];
      if (i) {
        pending.delete(i);
        t.fn();
      }
    },
    count: () => pending.size,
  };
}

test("sessão: criar, bloquear, destravar; a passphrase não é guardada", async () => {
  const store = memoryStore();
  const timers = fakeTimers();
  let locked = 0;
  const s = createSession({ store, timers, onLock: () => locked++, ...FAST });
  assert.equal(await s.status(), "none");

  const created = await s.create({ mnemonic: ABANDON, passphrase: "segredo", password: PW });
  assert.ok(created.address.startsWith("brdc1"));
  assert.equal(await s.status(), "unlocked");

  // o que foi guardado não contém a frase, a passphrase nem a senha
  const dump = JSON.stringify(await s.exportVault());
  for (const forbidden of ["abandon", "segredo", PW, created.address]) assert.ok(!dump.includes(forbidden), forbidden);

  s.lock();
  assert.equal(locked, 1);
  assert.equal(await s.status(), "locked");
  assert.throws(() => s.account(), /bloqueada/);

  // mesma passphrase: abre a mesma carteira
  const ok = await s.unlock({ password: PW, passphrase: "segredo" });
  assert.equal(ok.address, created.address);
  assert.equal(ok.matchesVault, true);
  s.lock();

  // passphrase diferente: abre OUTRA carteira e a sessão avisa
  const other = await s.unlock({ password: PW, passphrase: "outra" });
  assert.equal(other.matchesVault, false);
  assert.notEqual(other.address, created.address);
  s.lock();

  // sem passphrase: também é outra carteira
  const none = await s.unlock({ password: PW, passphrase: "" });
  assert.equal(none.matchesVault, false);
  s.lock();

  await assert.rejects(() => s.unlock({ password: "senha errada demais 99", passphrase: "segredo" }), VaultError);
  assert.equal(await s.status(), "locked");
});

test("sessão: assinar só com a carteira destravada; bloquear por inatividade", async () => {
  const timers = fakeTimers();
  const s = createSession({ store: memoryStore(), timers, idleMs: 1234, ...FAST });
  await s.create({ mnemonic: ABANDON, password: PW });
  const sig = await s.account().sign(new Uint8Array([1, 2, 3]));
  assert.equal(sig.length, 64);
  assert.equal(timers.count(), 1);

  timers.fire(); // o prazo de inatividade estourou
  assert.equal(await s.status(), "locked");
  assert.throws(() => s.account(), /bloqueada/);
  assert.equal(timers.count(), 0);
});

test("sessão: frase inválida e destravar sem cofre", async () => {
  const s = createSession({ store: memoryStore(), ...FAST });
  await assert.rejects(() => s.create({ mnemonic: "frase invalida", password: PW }), /frase inválida/);
  await assert.rejects(() => s.unlock({ password: PW }), /não há carteira/);
  assert.equal(await s.status(), "none");
});

test("sessão: frase nova válida (24 palavras) e apagar o cofre", async () => {
  const s = createSession({ store: memoryStore(), ...FAST });
  const m = await s.newMnemonic();
  assert.equal(m.split(" ").length, 24);
  assert.notEqual(m, await s.newMnemonic());
  await s.create({ mnemonic: m, password: PW });
  await s.erase();
  assert.equal(await s.status(), "none");
  assert.equal(await s.exportVault(), null);
});
