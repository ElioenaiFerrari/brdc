// Contratos entre partes no navegador (Fase 5/6): montar a transação (tipos 20 e 21), saber quais ações cada
// parte pode fazer e MOSTRAR, antes de assinar, o que cada ação faz com o dinheiro. As regras vêm do Elixir:
// `generated/contract_templates.json` é exportado de `BrdcLedger.ContractTemplates` (um teste acusa se ficar
// desatualizado). Todos os valores em BigInt.
import templates from "../generated/contract_templates.json" with { type: "json" };
import { concat, fixed, stringField, u32, u64 } from "./bytes.mjs";
import { decodeAddress } from "./wallet.mjs";
import { signingBytes } from "./tx.mjs";

export const TEMPLATES = templates;
export const KIND_CREATE = 20;
export const KIND_ACT = 21;

/** Carga de "criar contrato": modelo, id, parte B (endereço brdc1…) e termos (BigInt, na ordem do modelo). */
export function createPayload(template, id, partyBAddress, terms) {
  return concat(
    stringField(template),
    stringField(id),
    fixed(decodeAddress(partyBAddress), 32),
    u32(terms.length),
    ...terms.map((t) => u64(t)),
  );
}

/** Carga de "agir": id e nome da transição. */
export const actPayload = (id, action) => concat(stringField(id), stringField(action));

/** Transação de contrato (ainda sem assinatura) com a taxa de contrato da rede. */
export function buildContractTx({ kind, info, senderPublicKey, payload }) {
  const tx = {
    chainId: info.chainId,
    kind,
    nonce: BigInt(info.nonce),
    fee: BigInt(info.contractFee),
    senderPublicKey,
    payload,
  };
  return { tx, fee: tx.fee, size: signingBytes(tx).length + 64 };
}

// --- expressões do modelo (mesma semântica do Elixir: `sub` não fica negativo) -----------------------

/** `ctx` = { terms, vars, escrow, time }: todos BigInt (terms e vars são objetos nome -> BigInt). */
export function evalExpr(expr, ctx) {
  if (expr === "time") return ctx.time;
  if (expr === "escrow") return ctx.escrow;
  const [op, a, b] = expr;
  switch (op) {
    case "term":
      return ctx.terms[a];
    case "var":
      return ctx.vars[a] ?? 0n;
    case "const":
      return BigInt(a);
    case "add":
      return evalExpr(a, ctx) + evalExpr(b, ctx);
    case "sub": {
      const d = evalExpr(a, ctx) - evalExpr(b, ctx);
      return d < 0n ? 0n : d;
    }
    case "mul":
      return evalExpr(a, ctx) * evalExpr(b, ctx);
    case "min": {
      const x = evalExpr(a, ctx);
      const y = evalExpr(b, ctx);
      return x < y ? x : y;
    }
    default:
      throw new Error(`expressão desconhecida: ${op}`);
  }
}

/** Condições de tempo e contagem. Devolve `{ ok: true }` ou `{ ok: false, reason }`. */
export function checkGuards(guards, ctx) {
  for (const g of guards) {
    const [kind, v, t] = g;
    const val = ctx.vars[v] ?? 0n;
    if (kind === "before" && !(ctx.time < val)) return { ok: false, reason: "too_late", until: val };
    if (kind === "at_or_after" && !(ctx.time >= val)) return { ok: false, reason: "too_early", at: val };
    if (kind === "var_lt_term" && !(val < ctx.terms[t])) return { ok: false, reason: "not_ready" };
    if (kind === "var_eq_term" && !(val === ctx.terms[t])) return { ok: false, reason: "not_ready" };
  }
  return { ok: true };
}

/**
 * O que os efeitos fazem com o dinheiro, em ordem. Devolve linhas estruturadas:
 * { type: "lock" | "release" | "pay", party, to?, amount } (party/to são "a" ou "b").
 */
export function describeEffects(effects, ctx) {
  const state = { ...ctx, vars: { ...ctx.vars } };
  const lines = [];
  for (const e of effects) {
    const [op, p1, p2, p3] = e;
    if (op === "lock") {
      const amount = evalExpr(p2, state);
      state.escrow += amount;
      lines.push({ type: "lock", party: p1, amount });
    } else if (op === "release") {
      const want = evalExpr(p2, state);
      const amount = want < state.escrow ? want : state.escrow;
      state.escrow -= amount;
      lines.push({ type: "release", party: p1, amount });
    } else if (op === "pay") {
      lines.push({ type: "pay", party: p1, to: p2, amount: evalExpr(p3, state) });
    } else if (op === "set_var") {
      state.vars[p1] = evalExpr(p2, state);
    } else if (op === "inc_var") {
      state.vars[p1] = (state.vars[p1] ?? 0n) + 1n;
    }
  }
  return lines;
}

const toBig = (obj) => Object.fromEntries(Object.entries(obj ?? {}).map(([k, v]) => [k, BigInt(v)]));

/** Contexto de avaliação a partir de um contrato do nó (números em texto ou BigInt) e do horário do bloco. */
export const contextOf = (contract, time) => ({
  terms: toBig(contract.terms),
  vars: toBig(contract.vars),
  escrow: BigInt(contract.escrow),
  time: BigInt(time),
});

/**
 * Ações que `role` ("a" ou "b") pode tentar no estado atual do contrato, com o que cada uma faz com o
 * dinheiro e se as condições de tempo já valem. O nó é quem decide de verdade.
 */
export function availableActions(contract, role, time) {
  const t = templates[contract.template];
  if (!t) return [];
  const ctx = contextOf(contract, time);
  return Object.entries(t.transitions)
    .filter(([, tr]) => tr.from === contract.state && (tr.actor === role || tr.actor === "any"))
    .map(([name, tr]) => ({
      name,
      ...checkGuards(tr.guards, ctx),
      to: tr.to,
      lines: describeEffects(tr.effects, ctx),
    }));
}

/** O que acontece ao CRIAR o contrato (ex.: no empréstimo, o credor trava o principal). */
export function creationLines(templateId, terms) {
  const t = templates[templateId];
  const names = t.terms;
  const ctx = {
    terms: Object.fromEntries(names.map((n, i) => [n, BigInt(terms[i])])),
    vars: {},
    escrow: 0n,
    time: 0n,
  };
  return describeEffects(t.initial.effects, ctx);
}
