// Máscara de dinheiro e núcleo do efeito de letras (make js-test).
import test from "node:test";
import assert from "node:assert/strict";
import { maskMoney, parseAmount } from "./amount.mjs";
import { scrambleFrame, loadingFrame, glyphFor, durationFor, ease } from "./scramble.mjs";

const type = (raw, data, caret = raw.length) => maskMoney(raw, caret, { inputType: "insertText", data });
const paste = (raw) => maskMoney(raw, raw.length, { inputType: "insertFromPaste" });
const edit = (raw, caret = raw.length) => maskMoney(raw, caret, { inputType: "deleteContentBackward" });

test("máscara: milhares, vírgula decimal, até 6 casas e zeros à esquerda", () => {
  assert.equal(type("1234", "4").text, "1.234");
  assert.equal(type("1234567", "7").text, "1.234.567");
  assert.equal(type("1234567,89", "9").text, "1.234.567,89");
  assert.equal(type("12,1234567", "7").text, "12,123456");
  assert.equal(type("05", "5").text, "5");
  assert.equal(type("000", "0").text, "0");
  assert.equal(type("0", "0").text, "0");
  assert.equal(type("", null).text, "");
  assert.equal(type("12,", ",").text, "12,");
  assert.equal(type(",", ",").text, "0,");
  assert.equal(type("0,5", "5").text, "0,5");
});

test("máscara: o PONTO DIGITADO vira vírgula decimal (1.5 nunca vira 15) e o excedente é ignorado", () => {
  assert.equal(type("1.", ".").text, "1,");
  assert.equal(type("1.5", "5").text, "15"); // o 5 veio depois: o ponto já tinha sido convertido pelo evento anterior
  assert.equal(type("12,5.", ".").text, "12,5"); // já há vírgula: o ponto digitado some
  assert.equal(type("1,2,", ",").text, "1,2"); // segunda vírgula some
  assert.equal(type(".", ".").text, "0,");
});

test("máscara: apagar e editar nunca lê o ponto de milhar como decimal", () => {
  // "1.234" e apaga o 4: sobra "1.23": é o ponto de MILHAR da máscara, não um decimal
  assert.equal(edit("1.23").text, "123");
  assert.equal(edit("1.2").text, "12");
  assert.equal(edit("12.345.67").text, "1.234.567");
});

test("máscara: colagem de vários formatos", () => {
  assert.equal(paste("R$ 10,50").text, "10,50");
  assert.equal(paste("10.50").text, "10,50");
  assert.equal(paste("1.5").text, "1,5");
  assert.equal(paste("1.234").text, "1.234");
  assert.equal(paste("1.234.567").text, "1.234.567");
  assert.equal(paste("1.234,56").text, "1.234,56");
  assert.equal(paste("1,234.56").text, "1.234,56");
  assert.equal(paste("abc").text, "");
  assert.equal(paste("  12 345 ").text, "12.345");
});

test("máscara: limite de dígitos inteiros (cabe em 2^64 - 1)", () => {
  const big = type("99999999999999999", "9").text;
  assert.equal(big, "9.999.999.999.999");
  assert.notEqual(parseAmount(big), null);
});

test("máscara: o cursor fica depois do que foi digitado, mesmo quando a máscara põe pontos", () => {
  // digitar o 4 em "123|" -> "1.234|"
  const r = type("1234", "4", 4);
  assert.deepEqual([r.text, r.caret], ["1.234", 5]);
  // inserir no meio: "1.2|34" depois de digitar 9 em "1.2|34" -> raw "1.2934", caret 4
  const m = type("1.2934", "9", 4);
  assert.equal(m.text, "12.934");
  assert.equal(m.caret, 4); // depois do "9"
  // zero à esquerda removido não empurra o cursor
  const z = type("05", "5", 2);
  assert.deepEqual([z.text, z.caret], ["5", 1]);
  // vírgula inicial ganha o zero e o cursor vai depois da vírgula
  const c = type(",", ",", 1);
  assert.deepEqual([c.text, c.caret], ["0,", 2]);
});

test("PROPRIEDADE: qualquer entrada vira texto válido para o parser (ou vazio) e o cursor fica dentro", () => {
  const alphabet = "0123456789.,.,abc R$-";
  const infos = [{ inputType: "insertText", data: "." }, { inputType: "insertText", data: "5" }, { inputType: "insertFromPaste" }, { inputType: "deleteContentBackward" }, {}];
  let seed = 7;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  for (let n = 0; n < 4000; n++) {
    const len = Math.floor(rnd() * 22);
    let raw = "";
    for (let i = 0; i < len; i++) raw += alphabet[Math.floor(rnd() * alphabet.length)];
    const info = infos[Math.floor(rnd() * infos.length)];
    const caret = Math.floor(rnd() * (raw.length + 1));
    const { text, caret: c } = maskMoney(raw, caret, info);
    assert.match(text, /^(\d{1,3}(\.\d{3})*|\d+)?(,\d{0,6})?$/, JSON.stringify([raw, info, text]));
    if (text !== "") assert.notEqual(parseAmount(text), null, JSON.stringify([raw, info, text]));
    assert.ok(c >= 0 && c <= text.length, JSON.stringify([raw, caret, text, c]));
  }
});

test("máscara: é idempotente (reaplicar no resultado não muda nada)", () => {
  for (const t of ["1.234,56", "0,5", "12", "", "9.999.999.999.999,999999", "0,"]) {
    assert.equal(edit(t).text, t);
  }
});

// --- efeito de letras ----------------------------------------------------------------------------------

const seeded = (s = 1) => () => ((s = (s * 1664525 + 1013904223) & 0x7fffffff) / 0x7fffffff);

test("efeito: no começo tudo embaralhado, no fim o texto exato, e o tamanho nunca muda", () => {
  const text = "Saldo: 1.234,56 BRDC — Abrindo a carteira…";
  const n = Array.from(text).length;
  const start = scrambleFrame(text, 0, seeded());
  assert.equal(start.done, "");
  assert.equal(Array.from(start.rest).length, n);
  const end = scrambleFrame(text, 1, seeded());
  assert.deepEqual([end.done, end.rest], [text, ""]);
  for (const p of [0, 0.1, 0.33, 0.5, 0.9, 1]) {
    const f = scrambleFrame(text, p, seeded(3));
    assert.equal(Array.from(f.done + f.rest).length, n, `p=${p}`);
    assert.ok(text.startsWith(f.done), `p=${p}`);
  }
});

test("efeito: espaços e pontuação ficam no lugar; dígito vira dígito, letra vira letra da mesma caixa", () => {
  const text = "Ação 12, Teste: ok!";
  const { rest } = scrambleFrame(text, 0, seeded(9));
  const a = Array.from(text);
  const b = Array.from(rest);
  a.forEach((c, i) => {
    if (/\d/.test(c)) assert.match(b[i], /\d/);
    else if (/\p{Lu}/u.test(c)) assert.match(b[i], /[A-Z]/);
    else if (/\p{L}/u.test(c)) assert.match(b[i], /[a-z]/);
    else assert.equal(b[i], c);
  });
});

test("efeito: progresso fora de 0..1, vazio e emoji não quebram", () => {
  assert.deepEqual(scrambleFrame("", 0.5), { done: "", rest: "" });
  assert.equal(scrambleFrame("abc", -3, seeded()).done, "");
  assert.equal(scrambleFrame("abc", 9, seeded()).done, "abc");
  const e = scrambleFrame("ok 🔒 ok", 0.2, seeded());
  assert.equal(Array.from(e.done + e.rest).length, 7);
  assert.equal(glyphFor("🔒", seeded()), "🔒");
});

test("efeito de carregando: tamanho igual, pontuação intacta e com densidade 0 o texto não muda", () => {
  const t = "Conectando à rede…";
  assert.equal(loadingFrame(t, seeded(), 0), t);
  const f = loadingFrame(t, seeded(5), 0.5);
  assert.equal(Array.from(f).length, Array.from(t).length);
  assert.ok(f.endsWith("…"));
  assert.notEqual(loadingFrame(t, seeded(5), 1), t);
});

test("efeito: duração e suavização", () => {
  assert.equal(durationFor("a"), 350);
  assert.equal(durationFor("x".repeat(100)), 900);
  assert.ok(durationFor("x".repeat(15)) > 350 && durationFor("x".repeat(15)) < 900);
  assert.equal(ease(0), 0);
  assert.equal(ease(1), 1);
  assert.ok(ease(0.5) > 0.5);
  assert.equal(ease(5), 1);
});
