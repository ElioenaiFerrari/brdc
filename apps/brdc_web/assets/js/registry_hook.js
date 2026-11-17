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
import {
  registerDoc, vetoDoc, lienAddDoc, lienRemoveDoc, registerPayload, vetoPayload, lienAddPayload, lienRemovePayload,
  registerProposal, vetoProposal, lienAddProposal, lienRemoveProposal, describeOrganAction,
  KIND_REGISTER, KIND_VETO, KIND_LIEN_ADD, KIND_LIEN_REMOVE,
} from "./crypto/assets.mjs";

const TYPE_LABEL = { cnh: "CNH", identidade: "Identificação", casamento: "Certidão de casamento", divorcio: "Certidão de divórcio" };
const label = (t) => TYPE_LABEL[t] ?? t;
export const ERRORS = {
  asset_exists: "Já existe um bem com este id.",
  no_class: "Classe de bens desconhecida.",
  no_lien: "Gravame não encontrado neste bem.",
  lien_exists: "Este gravame já existe neste bem.",
  bad_id: "Id inválido (vazio, longo demais ou com caracteres não imprimíveis).",
  bad_kind: "Tipo de proposta desconhecido.",
  not_owner: "Só o dono do bem pode fazer isto.",
  not_buyer: "Só o comprador indicado pode aceitar.",
  deal_active: "Já há uma negociação deste bem.",
  has_lien: "O bem tem gravame; o órgão precisa removê-lo antes.",
  self_deal: "O comprador não pode ser você mesmo.",
  no_deal: "Não há negociação deste bem (já finalizada ou cancelada?).",
  no_asset: "Bem não encontrado.",
  offline: "Sem conexão com a rede. Tente de novo em instantes.",
  insufficient_funds: "Saldo insuficiente para a taxa.",
  bad_nonce: "A conta mudou enquanto você revisava. Revise de novo.",
  not_subject: "Só o titular pode contestar.",
  bad_status: "A credencial já mudou de estado.",
  window_closed: "O prazo já terminou (janela de contestação ou de veto).",
  window_open: "O prazo ainda não terminou (janela de contestação ou de veto).",
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

export const el = (tag, cls, text) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
};
export const when = (secs) => new Date(Number(secs) * 1000).toLocaleString("pt-BR");
export const TONE = { green: "brdc-chip brdc-chip-green", blue: "brdc-chip brdc-chip-blue", yellow: "brdc-chip brdc-chip-yellow", neutral: "brdc-chip" };

// assinatura do que o desenho depende: os dados e, de cada credencial, só se a janela/validade já passou
function signature(r, credentials) {
  const now = BigInt(r.time);
  return JSON.stringify(
    credentials.map((c) => [c, now >= BigInt(c.active_at), c.expires_at !== "0" && now >= BigInt(c.expires_at)]),
  );
}

// base comum: passos, erros, estado ocupado, preparar (dados públicos da rede) e enviar a transação assinada
export const Base = {
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

// --- órgão: propor, assinar e emitir (credenciais e bens) ---------------------------------------

const ACTIONS = {
  credential_issue: "Emitir credencial",
  asset_register: "Registrar bem",
  asset_veto: "Vetar venda de bem",
  lien_add: "Adicionar gravame",
  lien_remove: "Remover gravame",
};

// campos de cada ação: [nome, rótulo, tipo ("text" | "type" | "class" | "asset")]
const FORMS = {
  credential_issue: [["type", "Tipo de credencial", "type"], ["holder", "Titular (endereço brdc1…)", "text"], ["data", "Dados", "text"], ["ref", "Referência (só se o tipo exige: id da credencial anterior)", "text"]],
  asset_register: [["class", "Classe", "class"], ["asset", "Id do bem (ex.: casa-1)", "text"], ["owner", "Dono (endereço brdc1…)", "text"], ["meta", "Descrição do bem", "text"]],
  asset_veto: [["asset", "Bem com venda em andamento", "asset"]],
  lien_add: [["asset", "Bem", "asset"], ["lien", "Id do gravame (ex.: hipoteca-1)", "text"], ["ref", "Referência (contrato, processo…)", "text"]],
  lien_remove: [["asset", "Bem", "asset"], ["lien", "Id do gravame a remover", "text"]],
};

export const Organ = {
  ...Base,
  mounted() {
    this.reg = { types: [], classes: [], organ_assets: [], proposals: [], public_key: "", time: "0" };
    this.draft = null;
    this.fields = {};
    this.on("new", () => this.openNew());
    this.on("back", () => this.show("list"));
    this.on("propose", () => this.propose());
    this.on("confirm", () => this.draft?.run());
    this.q("[data-role='action']").addEventListener("change", () => this.drawForm());
    this.handleEvent("registry", (r) => {
      const sig = JSON.stringify([r.types, r.classes, r.organ_assets, r.proposals, r.public_key]);
      this.reg = r;
      this.el.hidden = r.types.length === 0 && r.classes.length === 0;
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
  assetOf(id) {
    return this.reg.organ_assets.find((a) => a.id === id);
  },
  classOf(id) {
    return this.reg.classes.find((c) => c.id === id);
  },

  render() {
    const parts = [
      ...this.reg.types.map((t) => `${label(t.id)} (${t.threshold} de ${t.organ_size})`),
      ...this.reg.classes.map((c) => `bens da classe ${c.id} (${c.threshold} de ${c.organ_size})`),
    ];
    this.q("[data-role='types']").textContent = parts.join(", ");
    this.q("[data-role='empty']").hidden = this.reg.proposals.length > 0;
    const list = this.q("[data-role='list']");
    list.textContent = "";
    for (const p of this.reg.proposals) list.appendChild(this.card(p));
  },

  // --- o que cada proposta é: título, linhas por extenso, documento e a transação final ---

  resolve(p, chainId) {
    const f = p.fields;
    const fmt = (u) => formatFull(u);
    switch (p.kind) {
      case "credential_issue": {
        const type = this.typeOf(f.type);
        const data = unhex(f.data);
        let text = "";
        if (type?.privacy !== "private") {
          try { text = fromUtf8(data); } catch { text = "(binário)"; }
        }
        return {
          title: `${label(f.type)} · ${f.id}`,
          lines: describeIssue({ typeLabel: label(f.type), id: f.id, subjectAddress: f.subject, dataText: text, privacy: type?.privacy ?? "public", ref: f.ref, threshold: p.threshold }),
          doc: issueDoc({ chainId, type: f.type, id: f.id, subjectAddress: f.subject, data, ref: f.ref }),
          tx: (approvals) => ({ kind: KIND_ISSUE, feeKey: "credential_fee", payload: issuePayload({ type: f.type, id: f.id, subjectAddress: f.subject, data, ref: f.ref, approvals }) }),
        };
      }
      case "asset_register": {
        const meta = unhex(f.meta);
        const metaText = fromUtf8(meta);
        return {
          title: `Registrar ${f.asset}`,
          lines: describeOrganAction("asset_register", { assetId: f.asset, cls: f.class, ownerAddress: f.owner, metaText, threshold: p.threshold }),
          doc: registerDoc({ chainId, cls: f.class, assetId: f.asset, ownerAddress: f.owner, meta }),
          tx: (approvals) => ({ kind: KIND_REGISTER, feeKey: "asset_register_fee", payload: registerPayload({ cls: f.class, assetId: f.asset, ownerAddress: f.owner, meta, approvals }) }),
        };
      }
      case "asset_veto": {
        const a = this.assetOf(f.asset);
        if (!a || a.deal !== "accepted") return null;
        return {
          title: `Vetar venda de ${f.asset}`,
          lines: describeOrganAction("asset_veto", { assetId: f.asset, buyerAddress: a.other, price: a.price, threshold: p.threshold, fmt }),
          doc: vetoDoc({ chainId, assetId: f.asset, rev: a.rev, buyerAddress: a.other, price: a.price, deadline: a.deadline }),
          tx: (approvals) => ({ kind: KIND_VETO, feeKey: null, payload: vetoPayload({ assetId: f.asset, approvals }) }),
        };
      }
      case "lien_add": {
        const a = this.assetOf(f.asset);
        if (!a) return null;
        return {
          title: `Gravame ${f.lien} em ${f.asset}`,
          lines: describeOrganAction("lien_add", { assetId: f.asset, lien: f.lien, ref: f.ref, threshold: p.threshold }),
          doc: lienAddDoc({ chainId, assetId: f.asset, rev: a.rev, lien: f.lien, ref: f.ref }),
          tx: (approvals) => ({ kind: KIND_LIEN_ADD, feeKey: null, payload: lienAddPayload({ assetId: f.asset, lien: f.lien, ref: f.ref, approvals }) }),
        };
      }
      case "lien_remove": {
        const a = this.assetOf(f.asset);
        const i = a ? a.lien_ids.indexOf(f.lien) : -1;
        if (i < 0) return null;
        const ref = a.lien_refs[i];
        return {
          title: `Remover gravame ${f.lien} de ${f.asset}`,
          lines: describeOrganAction("lien_remove", { assetId: f.asset, lien: f.lien, ref, threshold: p.threshold }),
          doc: lienRemoveDoc({ chainId, assetId: f.asset, rev: a.rev, lien: f.lien, ref }),
          tx: (approvals) => ({ kind: KIND_LIEN_REMOVE, feeKey: null, payload: lienRemovePayload({ assetId: f.asset, lien: f.lien, approvals }) }),
        };
      }
      default:
        return null;
    }
  },

  // para o cartão da lista (sem rede): título e linhas
  preview(p) {
    try {
      const r = this.resolve(p, "");
      return r ?? { title: `${ACTIONS[p.kind] ?? p.kind}`, lines: ["Os dados do bem mudaram; esta proposta pode ter caducado."] };
    } catch {
      return { title: ACTIONS[p.kind] ?? p.kind, lines: [] };
    }
  },

  card(p) {
    const r = this.preview(p);
    const li = el("li", "brdc-inset space-y-3 p-4");
    const head = el("div", "flex items-start justify-between gap-3");
    head.appendChild(el("p", "font-semibold", r.title));
    head.appendChild(el("span", p.approvals.length >= p.threshold ? TONE.green : TONE.yellow, `${p.approvals.length} de ${p.threshold} assinaturas`));
    li.appendChild(head);
    for (const line of r.lines.slice(0, 3)) li.appendChild(el("p", "text-sm text-[var(--brdc-muted)]", line));
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

  // --- nova ação ---

  available() {
    const a = [];
    if (this.reg.types.length) a.push("credential_issue");
    if (this.reg.classes.length) a.push("asset_register");
    if (this.reg.organ_assets.some((x) => x.deal === "accepted")) a.push("asset_veto");
    if (this.reg.organ_assets.length) a.push("lien_add");
    if (this.reg.organ_assets.some((x) => x.lien_ids.length)) a.push("lien_remove");
    return a;
  },

  openNew() {
    const sel = this.q("[data-role='action']");
    sel.textContent = "";
    for (const k of this.available()) {
      const o = el("option", "", ACTIONS[k]);
      o.value = k;
      sel.appendChild(o);
    }
    this.drawForm();
    this.step("new");
  },

  drawForm() {
    const kind = this.q("[data-role='action']").value;
    const box = this.q("[data-role='form']");
    box.textContent = "";
    this.fields = {};
    for (const [name, text, type] of FORMS[kind] ?? []) {
      const wrap = el("label", "block text-sm text-[var(--brdc-muted)]", text);
      let input;
      if (type === "text") {
        input = el("input", "brdc-input mt-1");
        input.type = "text";
        input.autocomplete = "off";
        input.spellcheck = false;
        if (name === "holder" || name === "owner") input.className += " font-mono text-sm";
      } else {
        input = el("select", "brdc-input mt-1");
        const items = type === "type" ? this.reg.types.map((t) => [t.id, label(t.id)])
          : type === "class" ? this.reg.classes.map((c) => [c.id, c.id])
          : this.reg.organ_assets
              .filter((a) => (kind === "asset_veto" ? a.deal === "accepted" : kind === "lien_remove" ? a.lien_ids.length > 0 : true))
              .map((a) => [a.id, `${a.id} (${a.class})`]);
        for (const [v, t] of items) {
          const o = el("option", "", t);
          o.value = v;
          input.appendChild(o);
        }
      }
      wrap.appendChild(input);
      box.appendChild(wrap);
      this.fields[name] = input;
    }
  },

  async propose() {
    this.error("");
    const kind = this.q("[data-role='action']").value;
    const v = (n) => this.fields[n]?.value?.trim() ?? "";
    const needAddress = (a, who) => {
      try { decodeAddress(a); return true; } catch { this.error(`Endereço ${who} inválido. Confira todos os caracteres.`); return false; }
    };
    let body, note = "";
    if (kind === "credential_issue") {
      const t = this.typeOf(v("type"));
      if (!needAddress(v("holder"), "do titular")) return;
      if (!v("data")) return this.error("Informe os dados da credencial.");
      const id = `${t.id}-${hex(crypto.getRandomValues(new Uint8Array(3)))}`;
      let data = utf8(this.fields.data.value);
      if (t.privacy === "private") {
        const salt = crypto.getRandomValues(new Uint8Array(16));
        note = `GUARDE e entregue ao titular, por fora da rede: dados "${this.fields.data.value}" e sal ${hex(salt)}.`;
        data = commitment(salt, data);
      }
      body = proposalFields({ type: t.id, id, subjectAddress: v("holder"), data, ref: v("ref") });
    } else if (kind === "asset_register") {
      if (!v("asset") || !v("meta")) return this.error("Informe o id e a descrição do bem.");
      if (!needAddress(v("owner"), "do dono")) return;
      body = registerProposal({ cls: v("class"), assetId: v("asset"), ownerAddress: v("owner"), meta: utf8(this.fields.meta.value) });
    } else if (kind === "asset_veto") {
      body = vetoProposal({ assetId: v("asset") });
    } else if (kind === "lien_add") {
      if (!v("lien") || !v("ref")) return this.error("Informe o id e a referência do gravame.");
      body = lienAddProposal({ assetId: v("asset"), lien: v("lien"), ref: v("ref") });
    } else {
      if (!v("lien")) return this.error("Informe o id do gravame a remover.");
      body = lienRemoveProposal({ assetId: v("asset"), lien: v("lien") });
    }
    this.busy(true);
    this.pushEvent("org:propose", { body: hex(body) }, (reply) => {
      this.busy(false);
      if (!reply?.ok) return this.error(ERRORS[reply?.error] ?? "A rede recusou a proposta.");
      this.q("[data-role='done-title']").textContent = "Proposta enviada";
      this.q("[data-role='done-text']").textContent = `Os outros membros do órgão veem a proposta na carteira deles e assinam. Quando houver assinaturas suficientes, qualquer membro emite. ${note}`;
      this.step("done");
    });
  },

  // --- revisão, assinatura e emissão ---

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
    this.prepare((info, account) => {
      const r = this.resolve(p, info.chain_id);
      if (!r) return this.error("Os dados do bem mudaram; esta proposta caducou.");
      const lines = [...r.lines, `Rede: ${info.chain_id}`, `Assinaturas já dadas: ${p.approvals.length} de ${p.threshold}`];
      this.showReview("Confira antes de assinar", "Assinar como membro do órgão", lines, async () => {
        this.busy(true);
        try {
          const approval = await approve(account, r.doc);
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

  reviewIssue(p) {
    this.prepare((info, account) => {
      const r = this.resolve(p, info.chain_id);
      if (!r) return this.error("Os dados do bem mudaram; esta proposta caducou.");
      const t = r.tx(p.approvals.map(unhex));
      const fee = BigInt(t.feeKey ? info[t.feeKey] : "0");
      if (fee > BigInt(info.balance)) return this.error("Saldo insuficiente para a taxa.");
      const tx = buildTx({ kind: t.kind, chainId: info.chain_id, nonce: info.nonce, fee, senderPublicKey: account.publicKey, payload: t.payload });
      const lines = [...r.lines, `Assinaturas reunidas: ${p.approvals.length} de ${p.threshold}`, `Taxa da rede: ${formatFull(fee)} BRDC (paga por quem envia)`, `Rede: ${info.chain_id}`];
      this.showReview("Emitir na rede", "Assinar e enviar", lines, () =>
        this.signAndSend(tx, (id) => {
          this.q("[data-role='done-title']").textContent = "Enviado";
          this.q("[data-role='done-text']").textContent = `Entra no próximo bloco. Id da transação: ${id}`;
          this.step("done");
        }),
      );
    });
  },
};
