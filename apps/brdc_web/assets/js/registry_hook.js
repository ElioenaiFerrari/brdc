// Hooks de credenciais (titular) e do órgão (assinatura coletiva) — ADR-0019/0022. O servidor só empurra dados
// públicos (credenciais, tipos, propostas com as aprovações); aqui o navegador desenha, mostra por extenso o que
// será assinado, assina com a chave não extraível e envia. Tudo com textContent (nunca HTML).
import { getSession } from "./wallet_state.js";
import { formatFull } from "./crypto/amount.mjs";
import { signTx, encodeTx } from "./crypto/tx.mjs";
import { hex, unhex, utf8, fromUtf8 } from "./crypto/bytes.mjs";
import { decodeAddress } from "./crypto/wallet.mjs";
import {
  issueDoc, approve, issuePayload, proposalFields, describeIssue, idPayload, buildTx, commitment, KIND_ISSUE, KIND_CONTEST, KIND_ACTIVATE,
} from "./crypto/proposals.mjs";

const TYPE_LABEL = { cnh: "CNH", identidade: "Identificação", casamento: "Certidão de casamento", divorcio: "Certidão de divórcio" };
const label = (t) => TYPE_LABEL[t] ?? t;
const ERRORS = {
  offline: "Sem conexão com a rede. Tente de novo em instantes.",
  insufficient_funds: "Saldo insuficiente para a taxa.",
  bad_nonce: "A conta mudou enquanto você revisava. Revise de novo.",
  not_subject: "Só o titular pode contestar.",
  bad_status: "A credencial já mudou de estado.",
  window_closed: "A janela de contestação já terminou.",
  window_open: "A janela de contestação ainda não terminou.",
  not_enough_approvals: "Ainda faltam assinaturas do órgão.",
  credential_exists: "Já existe uma credencial com este id.",
  proposal_exists: "Já há uma proposta para este id.",
  bad_approval: "Esta assinatura não vale para esta proposta (você não é do órgão ou o documento mudou).",
  no_type: "Tipo de credencial desconhecido.",
  bad_data: "Os dados não estão no formato do tipo (privado: compromisso de 32 bytes).",
  bad_ref: "A referência não confere (o tipo exige uma credencial ativa do mesmo titular).",
  too_many_proposals: "Há propostas demais esperando; tente depois.",
  no_proposal: "Proposta não encontrada (já emitida?).",
  duplicate: "Esta transação já foi enviada.",
  not_your_address: "A transação não é desta carteira.",
};

const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};
const when = (secs) => new Date(Number(secs) * 1000).toLocaleString("pt-BR");
const TONE = { green: "brdc-chip brdc-chip-green", blue: "brdc-chip brdc-chip-blue", yellow: "brdc-chip brdc-chip-yellow", neutral: "brdc-chip" };

// assinatura do que o desenho depende: os dados e, de cada credencial, só se a janela/validade já passou
function signature(r, credentials) {
  const now = BigInt(r.time);
  return JSON.stringify(
    credentials.map((c) => [c, now >= BigInt(c.active_at), c.expires_at !== "0" && now >= BigInt(c.expires_at)]),
  );
}

// base comum: passos, erros, estado ocupado, preparar (dados públicos da rede) e enviar a transação assinada
const Base = {
  q(s) { return this.el.querySelector(s); },
  step(name) {
    for (const s of this.el.querySelectorAll("[data-step]")) s.hidden = s.dataset.step !== name;
    this.error("");
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
      then(reply, account);
    });
  },
  async signAndSend(tx, onDone) {
    this.busy(true);
    try {
      const signed = await signTx(tx, getSession().account());
      this.pushEvent("wallet:submit", { tx: hex(encodeTx(signed)) }, (reply) => {
        this.busy(false);
        if (!reply?.ok) return this.error(ERRORS[reply?.error] ?? "A rede recusou a transação.");
        onDone(reply.id);
      });
    } catch {
      this.busy(false);
      this.error("Não foi possível assinar: a carteira pode ter bloqueado.");
    }
  },
  on(action, fn) {
    this.el.querySelectorAll(`[data-action="${action}"]`).forEach((b) => b.addEventListener("click", fn));
  },
};

// --- credenciais do titular ----------------------------------------------------------------------

export const Credentials = {
  ...Base,
  mounted() {
    this.reg = { credentials: [], time: "0" };
    this.draft = null;
    this.on("confirm", () => this.confirm());
    this.on("cancel", () => this.show("list"));
    this.handleEvent("registry", (r) => {
      // o relógio muda a cada atualização: só redesenha se algo visível mudou (senão o botão some debaixo do clique)
      const sig = signature(r, r.credentials);
      this.reg = r;
      if (sig === this.sig) return;
      this.sig = sig;
      if (!this.q("[data-step='list']").hidden) this.render();
    });
  },

  show(name) {
    this.step(name);
    if (name === "list") this.render();
  },

  stateOf(c) {
    const now = BigInt(this.reg.time);
    const expired = c.expires_at !== "0" && now >= BigInt(c.expires_at);
    if (c.status === "pending") return [`Pendente: contestação até ${when(c.active_at)}`, "yellow"];
    if (c.status === "active") return expired ? ["Expirada", "neutral"] : [c.expires_at === "0" ? "Ativa" : `Ativa até ${when(c.expires_at)}`, "green"];
    return [{ contested: "Contestada por você", vetoed: "Vetada pelo órgão", revoked: "Revogada pelo órgão" }[c.status] ?? c.status, "neutral"];
  },

  dataText(c) {
    const bytes = unhex(c.data);
    if (bytes.length === 32) return "Dados privados: só o compromisso está na rede.";
    try {
      return `Dados: ${fromUtf8(bytes)}`;
    } catch {
      return "Dados em formato binário.";
    }
  },

  render() {
    const list = this.q("[data-role='list']");
    list.textContent = "";
    this.q("[data-role='empty']").hidden = this.reg.credentials.length > 0;
    const now = BigInt(this.reg.time);
    for (const c of this.reg.credentials) {
      const li = el("li", "brdc-inset space-y-3 p-4");
      const head = el("div", "flex items-start justify-between gap-3");
      const left = el("div");
      left.appendChild(el("p", "font-semibold", `${label(c.type)} · ${c.id}`));
      left.appendChild(el("p", "text-sm text-[var(--brdc-muted)]", this.dataText(c)));
      head.appendChild(left);
      const [text, tone] = this.stateOf(c);
      head.appendChild(el("span", `${TONE[tone]} shrink-0`, text));
      li.appendChild(head);
      if (c.status === "pending") {
        const actions = el("div", "flex flex-wrap gap-2");
        const open = now < BigInt(c.active_at);
        const b = el("button", "brdc-chip brdc-chip-green cursor-pointer", open ? "Contestar (recusar)" : "Ativar");
        b.type = "button";
        b.addEventListener("click", () => this.review(c, open));
        actions.appendChild(b);
        li.appendChild(actions);
      }
      list.appendChild(li);
    }
  },

  review(c, contest) {
    this.prepare((info, account) => {
      const tx = buildTx({
        kind: contest ? KIND_CONTEST : KIND_ACTIVATE,
        chainId: info.chain_id,
        nonce: info.nonce,
        fee: 0n,
        senderPublicKey: account.publicKey,
        payload: idPayload(c.id),
      });
      this.draft = tx;
      const set = (r, t) => (this.q(`[data-role='${r}']`).textContent = t);
      set("r-what", contest ? "Contestar (recusar) esta credencial" : "Ativar a credencial (a janela terminou)");
      set("r-cred", `${label(c.type)} · ${c.id}`);
      set("r-effect", contest ? "A credencial é descartada e o id não pode ser reaproveitado. Só você, o titular, pode fazer isto, e só dentro da janela." : "A credencial passa a valer.");
      set("r-fee", `${formatFull(0n)} BRDC (sem taxa mínima)`);
      set("r-chain", info.chain_id);
      this.step("review");
    });
  },

  confirm() {
    if (this.draft) this.signAndSend(this.draft, (id) => ((this.q("[data-role='txid']").textContent = id), this.step("done")));
  },
};

// --- órgão: propor, assinar e emitir -------------------------------------------------------------

export const Organ = {
  ...Base,
  mounted() {
    this.reg = { types: [], proposals: [], public_key: "", time: "0" };
    this.draft = null;
    this.on("new", () => this.openNew());
    this.on("back", () => this.show("list"));
    this.on("propose", () => this.propose());
    this.on("confirm", () => this.draft?.run());
    this.q("[data-role='type']").addEventListener("change", () => this.typeHelp());
    this.handleEvent("registry", (r) => {
      const sig = JSON.stringify([r.types, r.proposals, r.public_key]);
      this.reg = r;
      this.el.hidden = r.types.length === 0;
      if (sig === this.sig) return;
      this.sig = sig;
      if (!this.q("[data-step='list']").hidden) this.render();
    });
  },

  show(name) {
    this.step(name);
    if (name === "list") this.render();
  },

  typeOf(id) {
    return this.reg.types.find((t) => t.id === id);
  },

  render() {
    this.q("[data-role='types']").textContent = this.reg.types.map((t) => `${label(t.id)} (${t.threshold} de ${t.organ_size})`).join(", ");
    this.q("[data-role='empty']").hidden = this.reg.proposals.length > 0;
    const list = this.q("[data-role='list']");
    list.textContent = "";
    for (const p of this.reg.proposals) list.appendChild(this.card(p));
  },

  card(p) {
    const type = this.typeOf(p.type);
    const li = el("li", "brdc-inset space-y-3 p-4");
    const head = el("div", "flex items-start justify-between gap-3");
    head.appendChild(el("p", "font-semibold", `${label(p.type)} · ${p.cred_id}`));
    head.appendChild(el("span", p.approvals.length >= p.threshold ? TONE.green : TONE.yellow, `${p.approvals.length} de ${p.threshold} assinaturas`));
    li.appendChild(head);
    for (const line of this.lines(p, type).slice(0, 3)) li.appendChild(el("p", "text-sm text-[var(--brdc-muted)]", line));
    const actions = el("div", "flex flex-wrap gap-2");
    const mine = p.approvals.some((a) => a.startsWith(this.reg.public_key));
    if (!mine) actions.appendChild(this.chip("Ler e assinar", () => this.reviewSign(p)));
    else actions.appendChild(el("span", "self-center text-xs text-[var(--brdc-muted)]", "Você já assinou"));
    if (p.approvals.length >= p.threshold) actions.appendChild(this.chip("Emitir na rede", () => this.reviewIssue(p)));
    li.appendChild(actions);
    return li;
  },

  chip(text, fn) {
    const b = el("button", "brdc-chip brdc-chip-green cursor-pointer", text);
    b.type = "button";
    b.addEventListener("click", fn);
    return b;
  },

  lines(p, type) {
    const data = unhex(p.data);
    let text = "";
    if (type?.privacy !== "private") {
      try {
        text = fromUtf8(data);
      } catch {
        text = "(binário)";
      }
    }
    return describeIssue({ typeLabel: label(p.type), id: p.cred_id, subjectAddress: p.subject, dataText: text, privacy: type?.privacy ?? "public", ref: p.ref, threshold: p.threshold });
  },

  // --- nova emissão ---

  openNew() {
    const sel = this.q("[data-role='type']");
    sel.textContent = "";
    for (const t of this.reg.types) {
      const o = el("option", "", label(t.id));
      o.value = t.id;
      sel.appendChild(o);
    }
    for (const r of ["holder", "data", "ref"]) this.q(`[data-role='${r}']`).value = "";
    this.typeHelp();
    this.step("new");
  },

  typeHelp() {
    const t = this.typeOf(this.q("[data-role='type']").value);
    const priv = t?.privacy === "private";
    this.q("[data-role='data-label']").textContent = priv ? "Dados (ficam só com o titular; a rede guarda apenas o compromisso)" : "Dados (públicos, ficam na rede)";
    const help = this.q("[data-role='privacy-help']");
    help.hidden = !priv;
    help.textContent = priv ? "Credencial privada: um sal aleatório é gerado e você vai entregar os dados e o sal ao titular, por fora da rede." : "";
  },

  async propose() {
    this.error("");
    const t = this.typeOf(this.q("[data-role='type']").value);
    const holder = this.q("[data-role='holder']").value.trim();
    const text = this.q("[data-role='data']").value;
    const ref = this.q("[data-role='ref']").value.trim();
    try {
      decodeAddress(holder);
    } catch {
      return this.error("Endereço do titular inválido. Confira todos os caracteres.");
    }
    if (!text.trim()) return this.error("Informe os dados da credencial.");
    const id = `${t.id}-${hex(crypto.getRandomValues(new Uint8Array(3)))}`;
    let data = utf8(text);
    let salt = null;
    if (t.privacy === "private") {
      salt = crypto.getRandomValues(new Uint8Array(16));
      data = commitment(salt, data);
    }
    const body = hex(proposalFields({ type: t.id, id, subjectAddress: holder, data, ref }));
    this.busy(true);
    this.pushEvent("org:propose", { body }, (reply) => {
      this.busy(false);
      if (!reply?.ok) return this.error(ERRORS[reply?.error] ?? "A rede recusou a proposta.");
      this.q("[data-role='done-title']").textContent = "Proposta enviada";
      this.q("[data-role='done-text']").textContent = salt
        ? `Os outros membros do órgão veem a proposta na carteira deles e assinam. GUARDE e entregue ao titular, por fora da rede: dados "${text}" e sal ${hex(salt)}.`
        : "Os outros membros do órgão veem a proposta na carteira deles e assinam. Quando houver assinaturas suficientes, qualquer membro emite.";
      this.step("done");
    });
  },

  // --- assinar ---

  showReview(title, confirmText, lines, run) {
    this.q("[data-role='review-title']").textContent = title;
    this.q("[data-role='confirm-label']").textContent = confirmText;
    const box = this.q("[data-role='review-lines']");
    box.textContent = "";
    for (const l of lines) box.appendChild(el("p", "", l));
    this.draft = { run };
    this.step("review");
  },

  reviewSign(p) {
    const type = this.typeOf(p.type);
    this.prepare((info, account) => {
      const doc = issueDoc({ chainId: info.chain_id, type: p.type, id: p.cred_id, subjectAddress: p.subject, data: unhex(p.data), ref: p.ref });
      const lines = [...this.lines(p, type), `Rede: ${info.chain_id}`, `Assinaturas já dadas: ${p.approvals.length} de ${p.threshold}`];
      this.showReview("Confira antes de assinar", "Assinar como membro do órgão", lines, async () => {
        this.busy(true);
        try {
          const approval = await approve(account, doc);
          this.pushEvent("org:approve", { id: p.id, approval: hex(approval) }, (reply) => {
            this.busy(false);
            if (!reply?.ok) return this.error(ERRORS[reply?.error] ?? "A rede recusou a assinatura.");
            this.q("[data-role='done-title']").textContent = "Assinatura enviada";
            this.q("[data-role='done-text']").textContent = `A proposta agora tem ${reply.approvals} de ${p.threshold} assinaturas.`;
            this.step("done");
          });
        } catch {
          this.busy(false);
          this.error("Não foi possível assinar: a carteira pode ter bloqueado.");
        }
      });
    });
  },

  // --- emitir (com as aprovações reunidas) ---

  reviewIssue(p) {
    const type = this.typeOf(p.type);
    this.prepare((info, account) => {
      const approvals = p.approvals.map(unhex);
      const payload = issuePayload({ type: p.type, id: p.cred_id, subjectAddress: p.subject, data: unhex(p.data), ref: p.ref, approvals });
      const tx = buildTx({ kind: KIND_ISSUE, chainId: info.chain_id, nonce: info.nonce, fee: info.credential_fee, senderPublicKey: account.publicKey, payload });
      if (BigInt(info.credential_fee) > BigInt(info.balance)) return this.error("Saldo insuficiente para a taxa de emissão.");
      const lines = [...this.lines(p, type), `Assinaturas reunidas: ${p.approvals.length} de ${p.threshold}`, `Taxa da rede: ${formatFull(info.credential_fee)} BRDC (paga por quem envia)`, `Rede: ${info.chain_id}`];
      this.showReview("Emitir a credencial", "Assinar e enviar a emissão", lines, () =>
        this.signAndSend(tx, (id) => {
          this.q("[data-role='done-title']").textContent = "Emissão enviada";
          this.q("[data-role='done-text']").textContent = `A credencial fica pendente durante a janela de contestação. Id da transação: ${id}`;
          this.step("done");
        }),
      );
    });
  },
};
