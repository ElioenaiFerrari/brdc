// Núcleo PURO do efeito "descriptografando" (letras que se embaralham e se resolvem, no estilo do Lumo da Proton).
// Sem DOM e sem relógio: o acaso entra como função (`rand`), então tudo é testável. O DOM fica em `ui_effects.js`.
const UP = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const LOW = "abcdefghijklmnopqrstuvwxyz";
const DIG = "0123456789";

const pick = (set, rand) => set[Math.min(Math.floor(rand() * set.length), set.length - 1)];

/** Um caractere embaralhado da mesma "classe": dígito vira dígito, letra vira letra (maiúscula/minúscula), o resto fica. */
export function glyphFor(ch, rand = Math.random) {
  if (/\d/.test(ch)) return pick(DIG, rand);
  if (/\p{Lu}/u.test(ch)) return pick(UP, rand);
  if (/\p{L}/u.test(ch)) return pick(LOW, rand);
  return ch;
}

/**
 * Quadro da revelação: `progress` de 0 a 1. A parte já resolvida (`done`) cresce da esquerda para a direita; o
 * resto (`rest`) são glifos embaralhados com o mesmo tamanho. Espaços e pontuação nunca mudam de lugar.
 */
export function scrambleFrame(text, progress, rand = Math.random) {
  const chars = Array.from(text);
  const k = Math.min(chars.length, Math.max(0, Math.floor(progress * chars.length)));
  return {
    done: chars.slice(0, k).join(""),
    rest: chars.slice(k).map((c) => glyphFor(c, rand)).join(""),
  };
}

/** Quadro de "carregando": o texto continua legível e uma fração dos caracteres vai cintilando em glifos. */
export function loadingFrame(text, rand = Math.random, density = 0.3) {
  return Array.from(text)
    .map((c) => (glyphFor(c, () => 0) !== c || /\p{L}|\d/u.test(c)) && rand() < density ? glyphFor(c, rand) : c)
    .join("");
}

/** Duração da revelação (ms): cerca de 35 ms por caractere, entre 350 e 900. */
export const durationFor = (text) => Math.min(900, Math.max(350, Array.from(text).length * 35));

/** Suaviza o avanço (começa rápido e desacelera ao resolver). */
export const ease = (p) => 1 - (1 - Math.min(1, Math.max(0, p))) ** 2;
