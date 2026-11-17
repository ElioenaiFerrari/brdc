// Cargas de bens no navegador = cargas do Elixir (vetores).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { offerPayload, assetPayload, describeStep } from "./assets.mjs";
import { hex } from "./bytes.mjs";

const vec = JSON.parse(readFileSync(new URL("../../../../../vectors/tx.json", import.meta.url)));

test("oferta e demais passos: cargas iguais às do Elixir", () => {
  assert.ok(vec.assets.length >= 2);
  for (const v of vec.assets) {
    assert.equal(hex(offerPayload({ asset: v.asset, buyerAddress: v.buyer, price: v.price })), v.offer_payload, v.asset);
    assert.equal(hex(assetPayload(v.asset)), v.asset_payload, v.asset);
  }
});

test("preço fora de 64 bits é recusado", () => {
  const v = vec.assets[0];
  assert.throws(() => offerPayload({ asset: v.asset, buyerAddress: v.buyer, price: (1n << 64n).toString() }));
});

test("o texto de cada passo traz o bem, o dinheiro e a janela", () => {
  const fmt = (u) => `${Number(u) / 1e6}`;
  const t = (s) => describeStep(s, { asset: "casa-1", price: "50000000", other: "brdc1x", vetoWindow: "60", fmt }).map((l) => l[0]).join(" | ");
  assert.match(t("offer"), /casa-1.*brdc1x.*50/s);
  assert.match(t("accept"), /50 BRDC saem.*60 segundos/s);
  assert.match(t("cancel"), /Cancelar a oferta/);
  assert.match(t("finalize"), /passa ao comprador/);
});
