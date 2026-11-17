// Contratos no navegador (make js-test): bytes iguais aos do Elixir e a prévia do que cada ação faz.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  TEMPLATES, KIND_CREATE, KIND_ACT, createPayload, actPayload, buildContractTx, evalExpr, checkGuards,
  describeEffects, availableActions, creationLines, contextOf,
} from "./contracts.mjs";
import { deriveAccount } from "./wallet.mjs";
import { signTx, encodeTx, signingBytes, txId } from "./tx.mjs";
import { hex } from "./bytes.mjs";

const vec = JSON.parse(readFileSync(new URL("../../../../../vectors/tx.json", import.meta.url)));

test("os três modelos vêm do Elixir, com termos e transições", () => {
  assert.deepEqual(Object.keys(TEMPLATES).sort(), ["aluguel", "compra-venda", "emprestimo"]);
  assert.deepEqual(TEMPLATES.aluguel.terms, ["rent", "period", "periods", "deposit", "grace"]);
  assert.equal(TEMPLATES["compra-venda"].transitions.accept.actor, "b");
  assert.deepEqual(TEMPLATES.emprestimo.initial.effects, [["lock", "a", ["term", "principal"]]]);
});

test("contratos assinados no JS = bytes, assinatura e id do Elixir", async () => {
  const me = await deriveAccount(vec.mnemonic, "");
  assert.ok(vec.contract_txs.length >= 5);
  for (const v of vec.contract_txs) {
    const payload =
      v.kind === KIND_CREATE
        ? createPayload(v.input.template, v.input.id, v.input.party_b, v.input.terms.map(BigInt))
        : actPayload(v.input.id, v.input.action);
    assert.equal(hex(payload), v.payload, `payload tipo ${v.kind}`);

    const info = { chainId: vec.chain_id, nonce: v.nonce, contractFee: v.fee };
    const { tx } = buildContractTx({ kind: v.kind, info, senderPublicKey: me.publicKey, payload });
    assert.equal(hex(signingBytes(tx)), v.signing_bytes);
    const signed = await signTx(tx, me);
    assert.equal(hex(signed.signature), v.signature);
    assert.equal(hex(encodeTx(signed)), v.encoded);
    assert.equal(hex(txId(signed)), v.txid);
  }
  assert.ok(vec.contract_txs.some((v) => v.kind === KIND_ACT));
});

test("criar: endereço inválido é recusado", () => {
  assert.throws(() => createPayload("compra-venda", "x", "brdc1invalido", [1n, 2n]));
});

test("expressões: sub não fica negativo, min, mul, add, constantes e variáveis", () => {
  const ctx = { terms: { a: 10n, b: 3n }, vars: { v: 4n }, escrow: 50n, time: 100n };
  assert.equal(evalExpr(["sub", ["term", "b"], ["term", "a"]], ctx), 0n);
  assert.equal(evalExpr(["sub", ["term", "a"], ["term", "b"]], ctx), 7n);
  assert.equal(evalExpr(["min", "escrow", ["mul", ["term", "a"], ["term", "b"]]], ctx), 30n);
  assert.equal(evalExpr(["add", "time", ["var", "v"]], ctx), 104n);
  assert.equal(evalExpr(["var", "inexistente"], ctx), 0n);
  assert.equal(evalExpr(["const", 7], ctx), 7n);
  assert.throws(() => evalExpr(["xyz", 1], ctx));
});

test("condições de tempo e de contagem", () => {
  const ctx = { terms: { n: 3n }, vars: { deadline: 1100n, paid: 3n }, escrow: 0n, time: 1000n };
  assert.deepEqual(checkGuards([["at_or_after", "deadline"]], ctx), { ok: false, reason: "too_early", at: 1100n });
  assert.deepEqual(checkGuards([["at_or_after", "deadline"]], { ...ctx, time: 1100n }), { ok: true });
  assert.equal(checkGuards([["before", "deadline"]], { ...ctx, time: 1100n }).reason, "too_late");
  assert.equal(checkGuards([["var_lt_term", "paid", "n"]], ctx).reason, "not_ready");
  assert.deepEqual(checkGuards([["var_eq_term", "paid", "n"]], ctx), { ok: true });
});

const sale = { template: "compra-venda", state: "funded", escrow: "1000000", terms: { price: "1000000", duration: "100" }, vars: { deadline: "1100" } };

test("compra e venda: o comprador confirma e o escrow vai ao vendedor; o vendedor pode devolver; prazo só depois", () => {
  const b = availableActions(sale, "b", 1050);
  assert.deepEqual(b.map((a) => a.name).sort(), ["confirm", "refund_expired"]);
  const confirm = b.find((a) => a.name === "confirm");
  assert.equal(confirm.ok, true);
  assert.deepEqual(confirm.lines, [{ type: "release", party: "a", amount: 1_000_000n }]);
  assert.equal(b.find((a) => a.name === "refund_expired").ok, false); // prazo ainda não venceu
  assert.equal(availableActions(sale, "b", 1100).find((a) => a.name === "refund_expired").ok, true);

  const a = availableActions(sale, "a", 1050);
  assert.deepEqual(a.map((x) => x.name).sort(), ["refund", "refund_expired"]);
  assert.deepEqual(a.find((x) => x.name === "refund").lines, [{ type: "release", party: "b", amount: 1_000_000n }]);
});

test("compra e venda aberta: o comprador aceita e trava o preço; só o vendedor cancela", () => {
  const open = { ...sale, state: "open", escrow: "0", vars: {} };
  const accept = availableActions(open, "b", 1000).find((a) => a.name === "accept");
  assert.deepEqual(accept.lines, [{ type: "lock", party: "b", amount: 1_000_000n }]);
  assert.deepEqual(availableActions(open, "a", 1000).map((a) => a.name), ["cancel"]);
  assert.deepEqual(availableActions({ ...open, state: "done" }, "a", 1000), []);
});

const rent = { template: "aluguel", state: "active", escrow: "200000", terms: { rent: "100000", period: "30", periods: "3", deposit: "200000", grace: "10" }, vars: { paid: "1", settle_at: "1100" } };

test("aluguel: a parcela é paga direto; a caução cobre o que falta; o resto volta", () => {
  const pay = availableActions(rent, "b", 1000).find((a) => a.name === "pay_rent");
  assert.equal(pay.ok, true);
  assert.deepEqual(pay.lines, [{ type: "pay", party: "b", to: "a", amount: 100_000n }]);

  // 1 paga de 3: faltam 2 x 100000 = 200000 -> a caução inteira (200000) vai ao locador
  const early = availableActions(rent, "b", 1000).find((a) => a.name === "settle");
  assert.equal(early.ok, false);
  const settle = availableActions(rent, "b", 1100).find((a) => a.name === "settle");
  assert.deepEqual(settle.lines, [{ type: "release", party: "a", amount: 200_000n }, { type: "release", party: "b", amount: 0n }]);

  // 2 pagas: falta 1 x 100000 -> metade para cada
  const two = { ...rent, vars: { ...rent.vars, paid: "2" } };
  const s2 = availableActions(two, "a", 1100).find((a) => a.name === "settle");
  assert.deepEqual(s2.lines, [{ type: "release", party: "a", amount: 100_000n }, { type: "release", party: "b", amount: 100_000n }]);

  // tudo pago: não há mais parcela e o locador pode liberar a caução antes do prazo
  const all = { ...rent, vars: { ...rent.vars, paid: "3" } };
  assert.equal(availableActions(all, "b", 1000).find((a) => a.name === "pay_rent").ok, false);
  const free = availableActions(all, "a", 1000).find((a) => a.name === "settle_paid");
  assert.equal(free.ok, true);
  assert.deepEqual(free.lines, [{ type: "release", party: "b", amount: 200_000n }]);
});

test("empréstimo: o credor trava o principal ao criar; o devedor recebe e devolve o combinado", () => {
  assert.deepEqual(creationLines("emprestimo", [1_000_000n, 1_100_000n, 604_800n]), [{ type: "lock", party: "a", amount: 1_000_000n }]);
  assert.deepEqual(creationLines("compra-venda", [1_000_000n, 3_600n]), []);

  const open = { template: "emprestimo", state: "open", escrow: "1000000", terms: { principal: "1000000", repay: "1100000", duration: "100" }, vars: {} };
  assert.deepEqual(availableActions(open, "b", 1000).find((a) => a.name === "accept").lines, [{ type: "release", party: "b", amount: 1_000_000n }]);
  assert.deepEqual(availableActions(open, "a", 1000).find((a) => a.name === "cancel").lines, [{ type: "release", party: "a", amount: 1_000_000n }]);

  const active = { ...open, state: "active", escrow: "0", vars: { deadline: "1100" } };
  assert.deepEqual(availableActions(active, "b", 1000).find((a) => a.name === "repay").lines, [{ type: "pay", party: "b", to: "a", amount: 1_100_000n }]);
  assert.equal(availableActions(active, "a", 1000).find((a) => a.name === "mark_default").ok, false);
  assert.equal(availableActions(active, "a", 1100).find((a) => a.name === "mark_default").ok, true);
});

test("modelo desconhecido e contexto", () => {
  assert.deepEqual(availableActions({ template: "x", state: "open", escrow: "0", terms: {}, vars: {} }, "a", 0), []);
  const c = contextOf(sale, 5);
  assert.equal(c.time, 5n);
  assert.equal(c.terms.price, 1_000_000n);
  assert.deepEqual(describeEffects([], c), []);
});
