// Valores da BRDC no navegador: leitura do que a pessoa digita e texto pt-BR. Espelha `BrdcLedger.Amount`
// (Elixir). Tudo em BigInt: valores vão até 2^64 - 1 e `Number` perde precisão acima de 2^53.
const UNIT = 1_000_000n;
const MAX = (1n << 64n) - 1n;

/**
 * "12,5" -> 12500000n. Devolve `null` se for inválido. O ponto só vale como separador de milhar bem
 * posicionado ("1.234,56"): "1.5" (um e meio, para quem digita em inglês) é RECUSADO, em vez de virar 15.
 */
export function parseAmount(text) {
  if (typeof text !== "string") return null;
  const parts = text.trim().split(",");
  if (parts.length > 2) return null;
  const [whole, frac = ""] = parts;
  if (!/^(\d+|\d{1,3}(\.\d{3})+)$/.test(whole)) return null;
  if (frac !== "" && !/^\d{1,6}$/.test(frac)) return null;
  const units = BigInt(whole.replaceAll(".", "")) * UNIT + BigInt(frac.padEnd(6, "0"));
  return units <= MAX ? units : null;
}

const thousands = (n) => n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");

/** 12480570000n -> "12.480,57" (trunca: nunca mostra mais do que a pessoa tem). */
export function formatAmount(units) {
  const u = BigInt(units);
  return `${thousands(u / UNIT)},${((u % UNIT) / 10_000n).toString().padStart(2, "0")}`;
}

/** 12480570000n -> "12.480,570000". */
export function formatFull(units) {
  const u = BigInt(units);
  return `${thousands(u / UNIT)},${(u % UNIT).toString().padStart(6, "0")}`;
}

/**
 * Máscara do campo de valor (pt-BR): agrupa milhares com ponto, vírgula decimal, até 6 casas e 13 dígitos
 * inteiros (cabe em 2^64 - 1 com as 6 casas). Devolve o texto formatado e onde deixar o cursor.
 *
 * Regras que protegem o dinheiro:
 * - o **ponto digitado** vira a vírgula decimal ("1.5" digitado = um e meio, nunca 15); se já há vírgula, é ignorado;
 * - o **ponto que a máscara mesma põe** nunca é lido como decimal: só se interpreta ponto em **colagem** (e na
 *   apagada/edição o que há são os pontos de milhar da própria máscara);
 * - colagem: "R$ 10,50" -> 10,50; "10.50" -> 10,50; "1.234" (3 dígitos depois do ponto) -> 1.234 (milhar);
 *   "1,234.56" (formato inglês) -> 1.234,56.
 *
 * `info` traz `inputType` e `data` do evento `input`. O resultado sempre passa em `parseAmount` (ou é vazio).
 */
export function maskMoney(raw, caret = raw.length, info = {}) {
  const inputType = info.inputType ?? "";
  let text = raw;
  let at = Math.min(Math.max(caret, 0), raw.length);

  if (inputType === "insertText" && info.data === "." && raw[at - 1] === ".") {
    // ponto digitado: vira a vírgula decimal (se já houver outra vírgula, o excedente é descartado abaixo)
    text = raw.slice(0, at - 1) + "," + raw.slice(at);
  } else if (/^insertFrom(Paste|Drop)/.test(inputType)) {
    text = normalizePasted(raw);
    at = text.length;
  }

  // quantos caracteres "que contam" (dígitos e vírgula) vêm antes do cursor
  let before = [...text.slice(0, at)].filter((c) => /[\d,]/.test(c)).length;

  const parts = text.split(",");
  const hasComma = parts.length > 1;
  const rawInt = parts[0].replace(/\D/g, "");
  let decimals = parts.slice(1).join("").replace(/\D/g, "").slice(0, 6);

  let intDigits = rawInt.replace(/^0+(?=\d)/, "").slice(0, 13);
  before -= rawInt.length - intDigits.length > 0 ? Math.min(rawInt.length - intDigits.length, before) : 0;
  if (intDigits === "" && hasComma) {
    intDigits = "0";
    before += 1;
  }
  if (!hasComma) decimals = "";

  const grouped = intDigits.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  const out = grouped + (hasComma ? `,${decimals}` : "");

  let pos = 0;
  let seen = 0;
  while (pos < out.length && seen < before) {
    if (/[\d,]/.test(out[pos])) seen += 1;
    pos += 1;
  }
  return { text: out, caret: pos };
}

// colagem: tira o que não é número e decide quem é o separador decimal
function normalizePasted(raw) {
  const t = raw.replace(/[^\d.,]/g, "");
  const lastComma = t.lastIndexOf(",");
  const lastDot = t.lastIndexOf(".");
  if (lastComma >= 0 && lastDot > lastComma) return t.replaceAll(",", "").replace(/\.(?=[^.]*$)/, ","); // 1,234.56
  if (lastComma >= 0) return t; // 1.234,56 ou 10,5: o ponto é milhar
  const dots = t.split(".").length - 1;
  if (dots === 1 && /^\d*\.\d{1,2}$/.test(t)) return t.replace(".", ","); // 10.50 -> decimal
  return t; // 1.234 e 1.234.567: milhar
}

