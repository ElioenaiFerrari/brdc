// Hook dos contratos entre partes (ADR-0017/0018/0022). O servidor manda a lista; aqui o navegador desenha, calcula
// o que cada ação faz com o dinheiro, MOSTRA em texto claro, assina com a chave não extraível e envia só a
// transação pronta. Tudo com textContent (nunca HTML).
import { getSession } from "./wallet_state.js";
import { UI, TYPE_FACTOR } from "./contracts_ui.js";
import { TEMPLATES, KIND_CREATE, KIND_ACT, createPayload, actPayload, buildContractTx, availableActions, creationLines } from "./crypto/contracts.mjs";
import { decodeAddress } from "./crypto/wallet.mjs";
import { parseAmount, formatFull } from "./crypto/amount.mjs";
import { signTx, encodeTx } from "./crypto/tx.mjs";
import { hex } from "./crypto/bytes.mjs";

const ERRORS = {
  offline: "Sem conexão com a rede. Tente de novo em instantes.",
  insufficient_funds: "Saldo insuficiente (inclui a taxa).",
  bad_nonce: "A conta mudou enquanto você revisava. Revise de novo.",
  fee_too_low: "A taxa mínima mudou. Revise de novo.",
  not_party: "Esta ação é da outra parte.",
  bad_state: "O contrato já mudou de estado.",
  too_early: "Ainda não é hora de fazer isto.",
  too_late: "O prazo desta ação já passou.",
  not_ready: "As condições para isto ainda não foram cumpridas.",
  contract_exists: "Já existe um contrato com este identificador.",
  bad_terms: "Condições inválidas para este tipo de contrato.",
  self_deal: "A outra parte não pode ser você.",
  no_contract: "Contrato não encontrado.",
  duplicate: "Esta transação já foi enviada.",
  not_your_address: "A transação não é desta carteira.",
};

const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};
const short = (a) => `${a.slice(0, 10)}…${a.slice(-6)}`;
const when = (secs) => new Date(Number(secs) * 1000).toLocaleString("pt-BR");
const TONE = { green: "brdc-chip brdc-chip-green", blue: "brdc-chip brdc-chip-blue", yellow: "brdc-chip brdc-chip-yellow", neutral: "brdc-chip" };

export const Contracts = {
  mounted() {
    this.q = (s) => this.el.querySelector(s);
    this.data = { contracts: [], time: "0", address: null };
    this.draft = null;
    const on = (action, fn) => this.el.querySelectorAll(`[data-action="${action}"]`).forEach((b) => b.addEventListener("click", fn));
    on("new", () => this.openNew());
    on("back", () => this.step("list"));
    on("cancel", () => this.step("list"));
    on("review-new", () => this.reviewNew());
    on("confirm", () => this.confirm());
    this.q("[data-role='template']").addEventListener("change", () => this.renderTerms());
    this.handleEvent("contracts", (payload) => {
      this.data = payload;
      if (!this.q("[data-step='list']").hidden) this.renderList();
    });
  },

  step(name) {
    for (const s of this.el.querySelectorAll("[data-step]")) s.hidden = s.dataset.step !== name;
    this.error("");
    if (name === "list") {
      this.draft = null;
      this.renderList();
    }
  },

  error(msg) {
    for (const e of this.el.querySelectorAll("[data-role='error']")) {
      const visible = !!msg && !e.closest("[data-step]").hidden;
      e.textContent = visible ? msg : "";
      e.hidden = !visible;
    }
  },

  busy(b) {
    this.el.setAttribute("aria-busy", b ? "true" : "false");
    for (const btn of this.el.querySelectorAll("button")) btn.disabled = b;
  },

  roleOf(c) {
    return c.a === this.data.address ? "a" : "b";
  },

  // --- lista -------------------------------------------------------------------------------------

  renderList() {
    const list = this.q("[data-role='list']");
    list.textContent = "";
    this.q("[data-role='empty']").hidden = this.data.contracts.length > 0;
    for (const c of this.data.contracts) list.appendChild(this.card(c));
  },

  card(c) {
    const ui = UI[c.template];
    const role = this.roleOf(c);
    const li = el("li", "brdc-inset space-y-3 p-4");
    const head = el("div", "flex items-start justify-between gap-3");
    const left = el("div");
    left.appendChild(el("p", "font-semibold", `${ui?.title ?? c.template} · ${c.id}`));
    const other = role === "a" ? c.b : c.a;
    left.appendChild(el("p", "text-sm text-[var(--brdc-muted)]", `Você é ${ui ? ui.roles[role].toLowerCase() : role} · com ${short(other)}`));
    head.appendChild(left);
    const [label, tone] = ui?.states[c.state] ?? [c.state, "neutral"];
    head.appendChild(el("span", TONE[tone] + " shrink-0", label));
    li.appendChild(head);

    const money = [];
    for (const [k, v] of Object.entries(c.terms)) {
      const t = ui?.terms[k];
      if (t) money.push(`${t.label.split(" (")[0]}: ${this.fmtTerm(t.type, v)}`);
    }
    li.appendChild(el("p", "text-xs text-[var(--brdc-muted)]", money.join(" · ")));
    if (BigInt(c.escrow) > 0n) li.appendChild(el("p", "text-sm text-[var(--brdc-yellow)]", `Retido na rede: ${formatFull(c.escrow)} BRDC`));

    const actions = el("div", "flex flex-wrap gap-2");
    for (const a of availableActions(c, role, this.data.time)) {
      const b = el("button", a.ok ? "brdc-chip brdc-chip-green cursor-pointer" : "brdc-chip opacity-60", ui?.actions[a.name] ?? a.name);
      b.type = "button";
      if (a.ok) b.addEventListener("click", () => this.reviewAct(c, a));
      else b.title = a.reason === "too_early" ? `Disponível a partir de ${when(a.at)}` : "Ainda não disponível";
      b.disabled = !a.ok;
      actions.appendChild(b);
      if (!a.ok && a.reason === "too_early") actions.appendChild(el("span", "self-center text-xs text-[var(--brdc-muted)]", `a partir de ${when(a.at)}`));
    }
    li.appendChild(actions);
    return li;
  },

  fmtTerm(type, v) {
    const n = BigInt(v);
    if (type === "brdc") return `${formatFull(n)} BRDC`;
    if (type === "minutes") return `${n / 60n} min`;
    if (type === "days") return `${n / 86_400n} dia(s)`;
    return n.toString();
  },

  // --- novo contrato ---------------------------------------------------------------------------------

  openNew() {
    const sel = this.q("[data-role='template']");
    if (!sel.options.length) {
      for (const id of Object.keys(UI).filter((k) => TEMPLATES[k])) {
        const o = el("option", "", UI[id]?.title ?? id);
        o.value = id;
        sel.appendChild(o);
      }
    }
    this.q("[data-role='party']").value = "";
    this.renderTerms();
    this.step("new");
  },

  renderTerms() {
    const id = this.q("[data-role='template']").value;
    const ui = UI[id];
    this.q("[data-role='template-help']").textContent = ui.help;
    this.q("[data-role='party-label']").textContent = ui.roles.b;
    const box = this.q("[data-role='terms']");
    box.textContent = "";
    for (const name of TEMPLATES[id].terms) {
      const t = ui.terms[name];
      const label = el("label", "block text-sm text-[var(--brdc-muted)]", t.label);
      const input = el("input", "brdc-input mt-1");
      input.type = "text";
      input.inputMode = t.type === "brdc" ? "decimal" : "numeric";
      input.autocomplete = "off";
      input.dataset.term = name;
      label.appendChild(input);
      box.appendChild(label);
    }
  },

  readTerm(type, text) {
    if (type === "brdc") {
      const v = parseAmount(text);
      return v !== null && v > 0n ? v : null;
    }
    if (!/^\d+$/.test(text.trim())) return null;
    const n = BigInt(text.trim());
    return n > 0n ? n * (TYPE_FACTOR[type] ?? 1n) : null;
  },

  async reviewNew() {
    this.error("");
    const id = this.q("[data-role='template']").value;
    const ui = UI[id];
    const party = this.q("[data-role='party']").value.trim();
    try {
      decodeAddress(party);
    } catch {
      return this.error("Endereço da outra parte inválido. Confira todos os caracteres.");
    }
    if (party === this.data.address) return this.error("A outra parte não pode ser você.");
    const terms = [];
    for (const name of TEMPLATES[id].terms) {
      const text = this.q(`[data-term="${name}"]`).value;
      const v = this.readTerm(ui.terms[name].type, text);
      if (v === null) return this.error(`Valor inválido em "${ui.terms[name].label}".`);
      terms.push(v);
    }
    const contractId = `${ui.short}-${hex(crypto.getRandomValues(new Uint8Array(3)))}`;
    this.prepare((info, account) => {
      const { tx, fee } = buildContractTx({ kind: KIND_CREATE, info, senderPublicKey: account.publicKey, payload: createPayload(id, contractId, party, terms) });
      const lines = creationLines(id, terms);
      const need = fee + lines.filter((l) => l.type === "lock").reduce((s, l) => s + l.amount, 0n);
      if (need > BigInt(info.balance)) return this.error(`Saldo insuficiente: você tem ${formatFull(info.balance)} BRDC e precisa de ${formatFull(need)}.`);
      this.show({
        tx, fee, info,
        what: `Criar contrato de ${ui.title.toLowerCase()} (você é ${ui.roles.a.toLowerCase()})`,
        contract: `${ui.title} · ${contractId}`,
        party,
        terms: TEMPLATES[id].terms.map((n, i) => `${ui.terms[n].label.split(" (")[0]}: ${this.fmtTerm(ui.terms[n].type, terms[i])}`),
        money: lines.length ? lines.map((l) => this.lineText(l, "a")) : ["Nenhum dinheiro sai da sua conta agora (só a taxa da rede)."],
      });
    });
  },

  // --- ação sobre um contrato ---------------------------------------------------------------------------

  reviewAct(c, a) {
    this.error("");
    const ui = UI[c.template];
    const role = this.roleOf(c);
    this.prepare((info, account) => {
      const { tx, fee } = buildContractTx({ kind: KIND_ACT, info, senderPublicKey: account.publicKey, payload: actPayload(c.id, a.name) });
      const out = a.lines.filter((l) => (l.type === "lock" && l.party === role) || (l.type === "pay" && l.party === role)).reduce((s, l) => s + l.amount, 0n);
      if (fee + out > BigInt(info.balance)) return this.error(`Saldo insuficiente: você precisa de ${formatFull(fee + out)} BRDC (valor + taxa).`);
      this.show({
        tx, fee, info,
        what: ui?.actions[a.name] ?? a.name,
        contract: `${ui?.title ?? c.template} · ${c.id}`,
        party: role === "a" ? c.b : c.a,
        terms: Object.entries(c.terms).filter(([k]) => ui?.terms[k]).map(([k, v]) => `${ui.terms[k].label.split(" (")[0]}: ${this.fmtTerm(ui.terms[k].type, v)}`),
        money: a.lines.filter((l) => l.amount > 0n).map((l) => this.lineText(l, role)).concat(a.lines.every((l) => l.amount === 0n) ? ["Nenhum dinheiro se move nesta ação (só a taxa da rede)."] : []),
      });
    });
  },

  lineText(l, role) {
    const x = `${formatFull(l.amount)} BRDC`;
    if (l.type === "lock") return l.party === role ? `Você deposita ${x} em escrow (retido pela rede).` : `A outra parte deposita ${x} em escrow.`;
    if (l.type === "release") return l.party === role ? `Você recebe ${x} do escrow.` : `A outra parte recebe ${x} do escrow.`;
    return l.party === role ? `Você paga ${x} direto à outra parte.` : `A outra parte paga ${x} direto a você.`;
  },

  // --- fluxo comum: preparar, revisar, assinar, enviar -----------------------------------------------------

  prepare(then) {
    let account;
    try {
      account = getSession().account();
    } catch {
      return this.error("A carteira está bloqueada.");
    }
    this.busy(true);
    this.pushEvent("wallet:prepare", {}, (reply) => {
      this.busy(false);
      if (!reply?.ok) return this.error(ERRORS.offline);
      then({ chainId: reply.chain_id, nonce: reply.nonce, contractFee: reply.contract_fee, balance: reply.balance }, account);
    });
  },

  show(d) {
    this.draft = d;
    const set = (role, text) => (this.q(`[data-role='${role}']`).textContent = text);
    const fill = (role, lines) => {
      const box = this.q(`[data-role='${role}']`);
      box.textContent = "";
      for (const t of lines) box.appendChild(el("p", "", t));
    };
    set("r-what", d.what);
    set("r-contract", d.contract);
    set("r-party", d.party);
    fill("r-terms", d.terms);
    fill("r-money", d.money);
    set("r-fee", `${formatFull(d.fee)} BRDC`);
    set("r-chain", d.info.chainId);
    this.step("review");
    this.draft = d;
  },

  async confirm() {
    if (!this.draft) return;
    this.busy(true);
    try {
      const signed = await signTx(this.draft.tx, getSession().account());
      this.pushEvent("wallet:submit", { tx: hex(encodeTx(signed)) }, (reply) => {
        this.busy(false);
        if (!reply?.ok) return this.error(ERRORS[reply?.error] ?? "A rede recusou a transação.");
        this.q("[data-role='txid']").textContent = reply.id;
        this.step("done");
      });
    } catch {
      this.busy(false);
      this.error("Não foi possível assinar: a carteira pode ter bloqueado.");
    }
  },
};
