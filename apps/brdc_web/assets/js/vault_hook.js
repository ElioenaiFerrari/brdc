// Hook da carteira (ADR-0006/0020/0021): TODA a parte sensível acontece aqui, no navegador.
// O servidor (LiveView) só recebe o ENDEREÇO (público) e o aviso de "bloqueada". Frase, passphrase e senha
// ficam em campos que o LiveView não enxerga (sem phx-change nem phx-submit) e são apagados da tela ao sair.
import { createSession } from "./crypto/session.mjs";
import { indexedDbStore } from "./crypto/store.mjs";
import { passwordProblems } from "./crypto/vault.mjs";
import { isValidMnemonic } from "./crypto/bip39.mjs";

const VIEWS = ["loading", "welcome", "create-words", "create-confirm", "create-secure", "import", "unlock", "unsupported"];

export const Vault = {
  async mounted() {
    this.root = this.el;
    this.q = (sel) => this.root.querySelector(sel);
    this.qa = (sel) => Array.from(this.root.querySelectorAll(sel));
    this.pending = { mnemonic: null };

    if (!globalThis.crypto?.subtle || !globalThis.indexedDB) return this.show("unsupported");
    try {
      // Ed25519 no WebCrypto: Chrome 137+, Firefox 129+, Safari 17+ (ADR-0020)
      await globalThis.crypto.subtle.generateKey({ name: "Ed25519" }, false, ["sign"]);
    } catch {
      return this.show("unsupported");
    }

    this.root.addEventListener("brdc:lock", () => this.session?.lock());
    this.root.addEventListener("brdc:copy", async () => {
      try {
        await navigator.clipboard.writeText(this.session.account().address); // endereço é público
      } catch {
        /* sem permissão da área de transferência: ignora */
      }
    });

    this.session = createSession({ store: indexedDbStore(), onLock: () => this.onLocked() });
    this.bind();
    for (const ev of ["pointerdown", "keydown"]) document.addEventListener(ev, () => this.session.touch(), { passive: true });
    document.addEventListener("visibilitychange", () => document.hidden && this.session.lock());

    await this.refresh();
  },

  // o LiveView reconectou e perdeu o estado: reenvia o que é público
  async reconnected() {
    if (this.session && (await this.session.status()) === "unlocked") this.announce();
  },

  async refresh() {
    const status = await this.session.status();
    if (status === "unlocked") return this.announce();
    this.show(status === "locked" ? "unlock" : "welcome");
  },

  show(view) {
    for (const v of VIEWS) {
      const el = this.q(`[data-view="${v}"]`);
      if (el) el.hidden = v !== view;
    }
    this.root.hidden = view === null;
    this.setError("");
  },

  hidePanel() {
    for (const v of VIEWS) {
      const el = this.q(`[data-view="${v}"]`);
      if (el) el.hidden = true;
    }
    this.root.hidden = true;
  },

  setError(msg, view) {
    for (const e of this.qa("[data-role='error']")) {
      const inView = !view || e.closest("[data-view]")?.dataset.view === view;
      e.textContent = inView ? msg : "";
      e.hidden = !(msg && inView);
    }
  },

  wipe() {
    for (const i of this.qa("input[type='password'], input[type='text'], textarea")) i.value = "";
    for (const w of this.qa("[data-role='words']")) w.textContent = "";
    for (const c of this.qa("[data-role='confirm-fields']")) c.textContent = "";
    this.pending.mnemonic = null;
  },

  announce() {
    const address = this.session.account().address;
    this.wipe();
    this.hidePanel();
    this.pushEvent("wallet:unlocked", { address });
  },

  onLocked() {
    this.pushEvent("wallet:locked", {});
    this.wipe();
    this.root.hidden = false;
    this.show("unlock");
  },

  on(action, fn) {
    for (const el of this.qa(`[data-action="${action}"]`)) el.addEventListener("click", fn);
  },

  bind() {
    for (const f of this.qa("form")) f.addEventListener("submit", (e) => e.preventDefault());

    this.on("start-create", async () => {
      this.pending.mnemonic = await this.session.newMnemonic();
      const list = this.q("[data-role='words']");
      list.textContent = "";
      this.pending.mnemonic.split(" ").forEach((w) => {
        const li = document.createElement("li");
        li.className = "brdc-inset px-3 py-2 text-sm";
        li.textContent = w; // textContent: nunca HTML
        list.appendChild(li);
      });
      this.q("[data-role='wrote']").checked = false;
      this.q("[data-action='words-next']").disabled = true;
      this.show("create-words");
    });

    this.q("[data-role='wrote']").addEventListener("change", (e) => {
      this.q("[data-action='words-next']").disabled = !e.target.checked;
    });

    this.on("words-next", () => {
      // pede 3 palavras em posições aleatórias para provar que a frase foi anotada
      const positions = new Set();
      while (positions.size < 3) positions.add(1 + (crypto.getRandomValues(new Uint32Array(1))[0] % 24));
      this.confirmPositions = [...positions].sort((a, b) => a - b);
      const box = this.q("[data-role='confirm-fields']");
      box.textContent = "";
      for (const p of this.confirmPositions) {
        const label = document.createElement("label");
        label.className = "block text-sm text-[var(--brdc-muted)]";
        label.textContent = `Palavra ${p}`;
        const input = document.createElement("input");
        input.type = "text";
        input.autocomplete = "off";
        input.autocapitalize = "none";
        input.spellcheck = false;
        input.className = "brdc-input mt-1";
        input.dataset.position = String(p);
        label.appendChild(input);
        box.appendChild(label);
      }
      this.show("create-confirm");
    });

    this.on("confirm-next", () => {
      const words = this.pending.mnemonic.split(" ");
      const ok = this.qa("[data-position]").every((i) => i.value.trim().toLowerCase() === words[Number(i.dataset.position) - 1]);
      if (!ok) return this.setError("Alguma palavra não confere. Confira a sua anotação.", "create-confirm");
      this.show("create-secure");
    });

    this.on("create-submit", async () => {
      const view = "create-secure";
      const pw = this.q("[data-view='create-secure'] [data-role='password']").value;
      const pw2 = this.q("[data-view='create-secure'] [data-role='password2']").value;
      const passphrase = this.q("[data-view='create-secure'] [data-role='passphrase']").value;
      const problems = passwordProblems(pw);
      if (problems.length) return this.setError(`Senha local: ${problems.join("; ")}.`, view);
      if (pw !== pw2) return this.setError("As senhas não são iguais.", view);
      await this.finish(() => this.session.create({ mnemonic: this.pending.mnemonic, passphrase, password: pw }), view);
    });

    this.on("start-import", () => this.show("import"));
    this.on("import-submit", async () => {
      const view = "import";
      const scope = "[data-view='import'] ";
      const mnemonic = this.q(scope + "[data-role='mnemonic']").value.trim().toLowerCase().replace(/\s+/g, " ");
      const passphrase = this.q(scope + "[data-role='passphrase']").value;
      const pw = this.q(scope + "[data-role='password']").value;
      const pw2 = this.q(scope + "[data-role='password2']").value;
      if (!(await isValidMnemonic(mnemonic))) return this.setError("Frase inválida: confira as palavras e a ordem.", view);
      const problems = passwordProblems(pw);
      if (problems.length) return this.setError(`Senha local: ${problems.join("; ")}.`, view);
      if (pw !== pw2) return this.setError("As senhas não são iguais.", view);
      await this.finish(() => this.session.create({ mnemonic, passphrase, password: pw }), view);
    });

    this.on("unlock-submit", async () => {
      const view = "unlock";
      const scope = "[data-view='unlock'] ";
      const pw = this.q(scope + "[data-role='password']").value;
      const passphrase = this.q(scope + "[data-role='passphrase']").value;
      this.setBusy(true);
      try {
        const r = await this.session.unlock({ password: pw, passphrase });
        if (!r.matchesVault) {
          this.q("[data-role='other-address']").textContent = r.address;
          this.q("[data-role='mismatch']").hidden = false;
          return;
        }
        this.announce();
      } catch (e) {
        this.setError(e?.name === "VaultError" ? "Senha incorreta." : "Não foi possível destravar.", view);
      } finally {
        this.setBusy(false);
      }
    });
    this.on("mismatch-continue", () => this.announce());
    this.on("mismatch-retry", () => {
      this.session.lock();
      this.q("[data-role='mismatch']").hidden = true;
    });

    this.on("back", () => {
      this.wipe();
      this.refresh();
    });
    this.on("lock", () => this.session.lock());
    this.on("erase", async () => {
      if (!this.q("[data-role='erase-confirm']")?.checked) return;
      await this.session.erase();
      this.pushEvent("wallet:locked", {});
      this.show("welcome");
    });
  },

  async finish(action, view) {
    this.setBusy(true);
    try {
      await action();
      this.announce();
    } catch (e) {
      this.setError(e?.message ?? "Não foi possível concluir.", view);
    } finally {
      this.setBusy(false);
    }
  },

  setBusy(busy) {
    this.root.setAttribute("aria-busy", busy ? "true" : "false");
    for (const b of this.qa("button")) b.disabled = busy || b.dataset.keepDisabled === "1";
    if (!busy) {
      const next = this.q("[data-action='words-next']");
      if (next && !this.q("[data-role='wrote']").checked) next.disabled = true;
    }
  },
};
