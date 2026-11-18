// Hook de envio (ADR-0020/0022). A transação é montada e ASSINADA aqui, no navegador, depois de mostrar em
// texto claro o que será assinado. O servidor só fornece dados públicos (rede, nonce, saldo, taxa) e repassa
// a transação pronta ao nó.
import { getSession } from "./wallet_state.js";
import { signingLabel } from "./ui_effects.js";
import { decodeAddress } from "./crypto/wallet.mjs";
import { parseAmount, formatAmount, formatFull } from "./crypto/amount.mjs";
import { buildTransfer } from "./crypto/send.mjs";
import { signTx, encodeTx } from "./crypto/tx.mjs";
import { hex } from "./crypto/bytes.mjs";

const ERRORS = {
  offline: "Sem conexão com a rede. Tente de novo em instantes.",
  insufficient_funds: "Saldo insuficiente (inclui a taxa).",
  bad_nonce: "A conta mudou enquanto você revisava. Revise de novo.",
  fee_too_low: "A taxa mínima mudou. Revise de novo.",
  wrong_chain: "Rede diferente da esperada.",
  duplicate: "Esta transação já foi enviada.",
  not_your_address: "A transação não é desta carteira.",
  bad_amount: "Valor inválido.",
  mempool_full: "A rede está cheia agora. Tente de novo.",
};

export const Send = {
  mounted() {
    this.q = (s) => this.el.querySelector(s);
    this.draft = null;
    const on = (action, fn) => this.q(`[data-action="${action}"]`).addEventListener("click", fn);
    on("review", () => this.review());
    on("confirm", () => this.confirm());
    on("cancel", () => this.step("form"));
    on("again", () => this.step("form"));
  },

  step(name) {
    for (const el of this.el.querySelectorAll("[data-step]")) el.hidden = el.dataset.step !== name;
    this.error("");
    if (name === "form") this.draft = null;
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

  review() {
    this.error("");
    const to = this.q("[data-role='to']").value.trim();
    const amount = parseAmount(this.q("[data-role='amount']").value);
    try {
      decodeAddress(to);
    } catch {
      return this.error("Endereço inválido. Confira todos os caracteres (ele tem verificação de erro de digitação).");
    }
    if (amount === null || amount <= 0n) {
      return this.error("Valor inválido. Use números e vírgula, por exemplo 12,5 (o ponto só separa milhares: 1.234,56).");
    }
    const account = getSession()?.account?.bind(getSession());
    let acc;
    try {
      acc = account();
    } catch {
      return this.error("A carteira está bloqueada.");
    }

    this.busy(true);
    this.pushEvent("wallet:prepare", {}, (reply) => {
      this.busy(false);
      if (!reply?.ok) return this.error(ERRORS.offline);
      const info = {
        chainId: reply.chain_id,
        nonce: reply.nonce,
        transferBase: reply.transfer_base,
        perByte: reply.per_byte,
      };
      const { tx, fee, total } = buildTransfer({ info, senderPublicKey: acc.publicKey, toAddress: to, amount });
      if (total > BigInt(reply.balance)) {
        return this.error(`Saldo insuficiente: você tem ${formatAmount(reply.balance)} BRDC e precisa de ${formatAmount(total)} (valor + taxa).`);
      }
      this.draft = { tx, to, amount, fee, total, chainId: info.chainId };
      this.q("[data-role='r-amount']").textContent = `${formatFull(amount)} BRDC`;
      this.q("[data-role='r-to']").textContent = to;
      this.q("[data-role='r-fee']").textContent = `${formatFull(fee)} BRDC`;
      this.q("[data-role='r-total']").textContent = `${formatFull(total)} BRDC`;
      this.q("[data-role='r-chain']").textContent = info.chainId;
      this.step("review");
    });
  },

  async confirm() {
    if (!this.draft) return;
    const restore = signingLabel(this.el);
    this.busy(true);
    try {
      const signed = await signTx(this.draft.tx, getSession().account());
      this.pushEvent("wallet:submit", { tx: hex(encodeTx(signed)) }, (reply) => {
        restore();
        this.busy(false);
        if (!reply?.ok) return this.error(ERRORS[reply?.error] ?? "A rede recusou a transação.");
        this.q("[data-role='txid']").textContent = reply.id;
        this.q("[data-role='to']").value = "";
        this.q("[data-role='amount']").value = "";
        this.step("done");
      });
    } catch {
      restore();
      this.busy(false);
      this.error("Não foi possível assinar: a carteira pode ter bloqueado.");
    }
  },
};
