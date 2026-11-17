// Cargas de bens no navegador = cargas do Elixir (vetores).
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { offerPayload, assetPayload, describeStep, registerDoc, vetoDoc, lienAddDoc, lienRemoveDoc, registerPayload, vetoPayload, lienAddPayload, lienRemovePayload } from "./assets.mjs";
import { deriveAccount } from "./wallet.mjs";
import { approve } from "./proposals.mjs";
import { utf8, unhex } from "./bytes.mjs";
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

test("ações do órgão sobre bens: documento, aprovações de 2 membros e carga = Elixir", async () => {
  const m1 = await deriveAccount(vec.mnemonic, "m1");
  const m2 = await deriveAccount(vec.mnemonic, "m2");
  assert.equal(vec.asset_ops.length, 4);
  for (const o of vec.asset_ops) {
    let doc, payload;
    const base = { chainId: vec.chain_id, assetId: o.asset };
    if (o.op === "register") {
      const i = { cls: o.class, assetId: o.asset, ownerAddress: o.owner, meta: utf8(o.meta) };
      doc = registerDoc({ chainId: vec.chain_id, ...i });
      payload = (approvals) => registerPayload({ ...i, approvals });
    } else if (o.op === "veto") {
      doc = vetoDoc({ ...base, rev: o.rev, buyerAddress: o.buyer, price: o.price, deadline: o.deadline });
      payload = (approvals) => vetoPayload({ assetId: o.asset, approvals });
    } else if (o.op === "lien_add") {
      doc = lienAddDoc({ ...base, rev: o.rev, lien: o.lien, ref: o.ref });
      payload = (approvals) => lienAddPayload({ assetId: o.asset, lien: o.lien, ref: o.ref, approvals });
    } else {
      doc = lienRemoveDoc({ ...base, rev: o.rev, lien: o.lien, ref: o.ref });
      payload = (approvals) => lienRemovePayload({ assetId: o.asset, lien: o.lien, approvals });
    }
    assert.equal(hex(doc), o.doc, `documento ${o.op}`);
    const aps = [await approve(m1, doc), await approve(m2, doc)];
    assert.deepEqual(aps.map(hex), o.approvals, `aprovações ${o.op}`);
    assert.equal(hex(payload(aps)), o.payload, `carga ${o.op}`);
  }
});
