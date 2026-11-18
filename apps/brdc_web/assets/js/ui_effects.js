// Efeitos de interface: máscara de dinheiro, texto "descriptografando" (letras que se embaralham e se resolvem, no
// estilo do Lumo da Proton) e estado de carregamento. Tudo por atributos, sem estilo embutido (CSP estrita):
//   data-money                campo de valor: máscara pt-BR (1.234,56) com cursor preservado
//   data-decrypt              texto que se revela sempre que o conteúdo muda (e na primeira aparição)
//   data-scramble-loading     texto de carregamento que fica cintilando; `data-loading-text` é o texto base
// Acessibilidade: o texto real fica sempre disponível a leitores de tela (trecho `.brdc-sr`) e quem pede "reduzir
// movimento" vê o texto direto, sem animação. A parte sem DOM está em `crypto/scramble.mjs` e `crypto/amount.mjs`.
import { maskMoney } from "./crypto/amount.mjs";
import { scrambleFrame, loadingFrame, durationFor, ease } from "./crypto/scramble.mjs";

const reduced = () => window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true;

// --- máscara de dinheiro ----------------------------------------------------------------------------------------

function onMoneyInput(e) {
  const input = e.target;
  if (!(input instanceof HTMLInputElement) || input.dataset.money === undefined) return;
  const caret = input.selectionStart ?? input.value.length;
  const { text, caret: at } = maskMoney(input.value, caret, { inputType: e.inputType, data: e.data });
  if (text !== input.value) input.value = text;
  // `setSelectionRange` só existe em campos de texto; em outros tipos o navegador lança, então protege
  try {
    input.setSelectionRange(at, at);
  } catch {
    /* sem seleção neste tipo de campo */
  }
}

// --- revelação "descriptografando" ---------------------------------------------------------------------------------

const state = new WeakMap(); // elemento -> { text, raf }
let observer = null;

// escreve no DOM sem que o nosso próprio observador reaja ao que acabamos de escrever
function quiet(fn) {
  fn();
  observer?.takeRecords();
}

const span = (cls) => {
  const s = document.createElement("span");
  if (cls) s.className = cls;
  return s;
};

/** Revela `text` em `el`: o que já foi resolvido cresce da esquerda, o resto fica embaralhado em verde. */
export function decrypt(el, text = currentText(el)) {
  const prev = state.get(el);
  if (prev?.raf) cancelAnimationFrame(prev.raf);
  const st = { text, raf: 0 };
  state.set(el, st);

  if (reduced() || text.trim() === "") {
    quiet(() => {
      el.textContent = text;
    });
    return;
  }

  const done = span();
  const rest = span("brdc-scr");
  const real = span("brdc-sr");
  done.setAttribute("aria-hidden", "true");
  rest.setAttribute("aria-hidden", "true");
  real.textContent = text; // leitores de tela leem o texto verdadeiro, nunca os glifos
  quiet(() => el.replaceChildren(done, rest, real));

  const total = durationFor(text);
  const start = performance.now();
  let last = -1000;

  const frame = (now) => {
    const p = (now - start) / total;
    if (p >= 1) {
      quiet(() => {
        el.textContent = text;
      });
      st.raf = 0;
      return;
    }
    if (now - last >= 45) {
      last = now;
      const f = scrambleFrame(text, ease(p));
      quiet(() => {
        done.textContent = f.done;
        rest.textContent = f.rest;
      });
    }
    st.raf = requestAnimationFrame(frame);
  };
  frame(start); // primeiro quadro já, sem piscar vazio; ele mesmo agenda os seguintes
}

// --- carregando --------------------------------------------------------------------------------------------------------

const loaders = new Set();
let loadTimer = null;

function paintLoader(el) {
  const base = el.dataset.loadingText ?? "";
  const shown = el.firstElementChild;
  if (shown?.dataset.loadingShown === "1") shown.textContent = loadingFrame(base);
}

/** Faz o texto de `el` cintilar enquanto durar o carregamento (ver `stopLoading`). */
export function startLoading(el) {
  if (loaders.has(el)) return;
  const base = (el.dataset.loadingText ?? el.textContent).trim();
  el.dataset.loadingText = base;
  el.classList.add("brdc-loading");
  if (reduced()) {
    quiet(() => {
      el.textContent = base;
    });
    return;
  }
  const shown = span();
  shown.dataset.loadingShown = "1";
  shown.setAttribute("aria-hidden", "true");
  const real = span("brdc-sr");
  real.textContent = base;
  quiet(() => el.replaceChildren(shown, real));
  loaders.add(el);
  paintLoader(el);
  loadTimer ??= setInterval(tickLoaders, 90);
}

function tickLoaders() {
  for (const el of loaders) {
    if (!el.isConnected) loaders.delete(el);
    else if (el.offsetParent !== null) quiet(() => paintLoader(el));
  }
  if (loaders.size === 0 && loadTimer) {
    clearInterval(loadTimer);
    loadTimer = null;
  }
}

/** Para de cintilar e devolve o texto base (ou `text`, se informado). */
export function stopLoading(el, text) {
  loaders.delete(el);
  el.classList.remove("brdc-loading");
  quiet(() => {
    el.textContent = text ?? el.dataset.loadingText ?? "";
  });
}

/**
 * Rótulo de botão em carregamento: mostra `text` cintilando e devolve a função que restaura o rótulo antigo.
 * Use em `try { … } finally { restore() }`.
 */
export function loadingLabel(button, text) {
  if (!button) return () => {};
  const previous = button.textContent;
  button.dataset.loadingText = text;
  startLoading(button);
  return () => {
    loaders.delete(button);
    button.classList.remove("brdc-loading");
    quiet(() => {
      button.textContent = previous;
    });
  };
}

/** Rótulo "Assinando e enviando…" cintilando no botão de confirmar da etapa visível de `root`. */
export function signingLabel(root, text = "Assinando e enviando…") {
  return loadingLabel(root.querySelector("[data-step]:not([hidden]) [data-action='confirm']"), text);
}

// --- observador -------------------------------------------------------------------------------------------------------

function scan(root) {
  if (root.matches?.("[data-decrypt]")) reveal(root);
  root.querySelectorAll?.("[data-decrypt]").forEach(reveal);
  if (root.matches?.("[data-scramble-loading]")) startLoading(root);
  root.querySelectorAll?.("[data-scramble-loading]").forEach(startLoading);
}

// o texto VERDADEIRO do elemento: com a animação em curso, `textContent` traz também os glifos embaralhados; o texto
// real fica no trecho `.brdc-sr` (que é também o que os leitores de tela leem)
function currentText(el) {
  const real = el.querySelector(":scope > .brdc-sr");
  return real ? real.textContent : el.textContent;
}

function reveal(el) {
  const text = currentText(el);
  if (state.get(el)?.text === text) return; // nada novo (ou é o que nós mesmos escrevemos)
  decrypt(el, text);
}

function onMutations(records) {
  const changed = new Set();
  for (const r of records) {
    const node = r.target.nodeType === 1 ? r.target : r.target.parentElement;
    const el = node?.closest?.("[data-decrypt]");
    if (el) changed.add(el);
    for (const n of r.addedNodes) if (n.nodeType === 1) scan(n);
  }
  changed.forEach(reveal);
}

/** Liga a máscara, o observador e faz a primeira varredura. Chame uma vez. */
export function installUiEffects() {
  if (observer) return;
  document.addEventListener("input", onMoneyInput, true);
  observer = new MutationObserver(onMutations);
  observer.observe(document.body, { subtree: true, childList: true, characterData: true });
  scan(document.body);
}
