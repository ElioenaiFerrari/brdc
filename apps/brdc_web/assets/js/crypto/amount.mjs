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
