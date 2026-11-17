// Bens do usuário (dono e comprador), ADR-0018. O servidor empurra dados públicos; aqui o navegador desenha, mostra
// por extenso cada passo e assina. A parte do órgão (registro, veto, gravames) vem na assinatura coletiva.
import { getSession } from "./wallet_state.js";
import { parseAmount, formatFull } from "./crypto/amount.mjs";
import { decodeAddress } from "./crypto/wallet.mjs";
import { fromUtf8, unhex } from "./crypto/bytes.mjs";
import { buildTx } from "./crypto/proposals.mjs";
import { offerPayload, assetPayload, describeStep, KIND_OFFER, KIND_ACCEPT, KIND_CANCEL, KIND_FINALIZE } from "./crypto/assets.mjs";
import { Base, ERRORS, el, when, TONE } from "./registry_hook.js";

const KIND = { offer: KIND_OFFER, accept: KIND_ACCEPT, cancel: KIND_CANCEL, finalize: KIND_FINALIZE };

const metaText = (a) => {
  try {
    return fromUtf8(unhex(a.meta));
  } catch {
    return "(binário)";
  }
};

// o desenho depende dos dados e, de cada bem em negociação, de a janela de veto já ter passado
const signature = (r) =>
  JSON.stringify(r.assets.map((a) => [a, a.deal === "accepted" && BigInt(r.time) >= BigInt(a.deadline)]));

export const Assets = {
  ...Base,
  mounted() {
    this.reg = { assets: [], time: "0" };
    this.draft = null;
    this.on("back", () => this.show("list"));
    this.on("offer-review", () => this.reviewOffer());
    this.on("confirm", () => this.confirm());
    this.handleEvent("registry", (r) => {
      const sig = signature(r);
      this.reg = r;
      this.el.hidden = r.assets.length === 0;
      if (sig === this.sig) return;
      this.sig = sig;
      if (!this.q("[data-step='list']").hidden) this.render();
    });
  },

  show(name) {
    this.step(name);
    if (name === "list") this.render();
  },

  fmt: (u) => formatFull(u),

  render() {
    const list = this.q("[data-role='list']");
    list.textContent = "";
    const now = BigInt(this.reg.time);
    for (const a of this.reg.assets) {
      const li = el("li", "brdc-inset space-y-3 p-4");
      const head = el("div", "flex items-start justify-between gap-3");
      const left = el("div");
      left.appendChild(el("p", "font-semibold", `${a.id} · ${a.class}`));
      left.appendChild(el("p", "text-sm text-[var(--brdc-muted)]", metaText(a)));
      head.appendChild(left);
      const [text, tone] = this.state(a, now);
      head.appendChild(el("span", `${TONE[tone]} shrink-0`, text));
      li.appendChild(head);
      const actions = el("div", "flex flex-wrap gap-2");
      for (const [label, fn] of this.actions(a, now)) actions.appendChild(this.chip(label, fn));
      if (actions.children.length) li.appendChild(actions);
      list.appendChild(li);
    }
  },

  state(a, now) {
    const lien = a.lien_ids.length > 0 ? " · com gravame" : "";
    if (a.deal === "none") return [a.role === "owner" ? `Seu${lien}` : "—", "green"];
    if (a.deal === "offered") return [a.role === "owner" ? "Oferta enviada" : "Oferta para você", "blue"];
    const done = now >= BigInt(a.deadline);
    return [done ? "Janela de veto encerrada" : `Janela de veto até ${when(a.deadline)}`, "yellow"];
  },

  actions(a, now) {
    const open = (step, extra = {}) => () => this.review(step, a, extra);
    if (a.role === "owner" && a.deal === "none") return a.lien_ids.length > 0 ? [] : [["Oferecer à venda", () => this.openOffer(a)]];
    if (a.role === "owner" && a.deal === "offered") return [["Cancelar oferta", open("cancel")]];
    if (a.role === "buyer" && a.deal === "offered") return [["Aceitar e pagar", open("accept")]];
    if (a.deal === "accepted" && now >= BigInt(a.deadline)) return [["Finalizar venda", open("finalize")]];
    return [];
  },

  chip(text, fn) {
    const b = el("button", "brdc-chip brdc-chip-green cursor-pointer", text);
    b.type = "button";
    b.addEventListener("click", fn);
    return b;
  },

  // --- oferta (precisa de comprador e preço) ---

  openOffer(a) {
    this.offerAsset = a;
    this.q("[data-role='offer-title']").textContent = `Oferecer "${a.id}" à venda`;
    this.q("[data-role='buyer']").value = "";
    this.q("[data-role='price']").value = "";
    this.step("offer");
  },

  reviewOffer() {
    this.error("");
    const a = this.offerAsset;
    const buyer = this.q("[data-role='buyer']").value.trim();
    const price = parseAmount(this.q("[data-role='price']").value);
    try {
      decodeAddress(buyer);
    } catch {
      return this.error("Endereço do comprador inválido. Confira todos os caracteres.");
    }
    if (price === null || price <= 0n) return this.error("Preço inválido. Exemplos: 1.500,50 ou 12,5");
    this.review("offer", a, { buyer, price });
  },

  // --- revisão e envio ---

  review(step, a, extra = {}) {
    this.prepare((info, account) => {
      const price = extra.price ?? BigInt(a.price);
      const payload = step === "offer" ? offerPayload({ asset: a.id, buyerAddress: extra.buyer, price }) : assetPayload(a.id);
      const fee = BigInt(info.asset_step_fee);
      if (fee > BigInt(info.balance)) return this.error("Saldo insuficiente para a taxa.");
      if (step === "accept" && fee + price > BigInt(info.balance)) return this.error("Saldo insuficiente: o preço fica retido e a taxa é cobrada à parte.");
      const lines = describeStep(step, { asset: a.id, price, other: extra.buyer ?? a.other, vetoWindow: a.veto_window, fmt: this.fmt });
      const box = this.q("[data-role='review-lines']");
      box.textContent = "";
      for (const [text, title] of lines) {
        const row = el("div");
        row.appendChild(el("p", "text-[var(--brdc-muted)]", title));
        row.appendChild(el("p", "font-semibold", text));
        box.appendChild(row);
      }
      const extraRows = [["Taxa da rede", `${this.fmt(fee)} BRDC`], ["Rede", info.chain_id]];
      for (const [t, v] of extraRows) {
        const row = el("div");
        row.appendChild(el("p", "text-[var(--brdc-muted)]", t));
        row.appendChild(el("p", "", v));
        box.appendChild(row);
      }
      this.draft = buildTx({ kind: KIND[step], chainId: info.chain_id, nonce: info.nonce, fee, senderPublicKey: account.publicKey, payload });
      this.step("review");
    });
  },

  confirm() {
    if (!this.draft) return;
    this.signAndSend(this.draft, (id) => {
      this.q("[data-role='txid']").textContent = id;
      this.step("done");
    });
  },
};
