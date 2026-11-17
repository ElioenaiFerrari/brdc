// Assinatura coletiva no navegador (make js-test): documento, aprovação e carga IGUAIS aos do Elixir.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { issueDoc, approve, issuePayload, proposalFields, describeIssue } from "./proposals.mjs";
import { deriveAccount } from "./wallet.mjs";
import { hex, unhex } from "./bytes.mjs";

const vec = JSON.parse(readFileSync(new URL("../../../../../vectors/tx.json", import.meta.url)));

test("documento, aprovações de dois membros e carga da emissão = Elixir (3 credenciais)", async () => {
  assert.ok(vec.issues.length >= 3);
  const m1 = await deriveAccount(vec.mnemonic, "m1");
  const m2 = await deriveAccount(vec.mnemonic, "m2");
  for (const v of vec.issues) {
    const data = unhex(v.data_hex);
    const input = { chainId: vec.chain_id, type: v.type, id: v.id, subjectAddress: v.subject, data, ref: v.ref };
    const doc = issueDoc(input);
    assert.equal(hex(doc), v.doc, `documento ${v.id}`);

    assert.deepEqual([hex(m1.publicKey), hex(m2.publicKey)], v.member_public_keys);
    const a1 = await approve(m1, doc);
    const a2 = await approve(m2, doc);
    assert.equal(a1.length, 96);
    assert.deepEqual([hex(a1), hex(a2)], v.approvals, `aprovações ${v.id}`);

    assert.equal(hex(issuePayload({ ...input, approvals: [a1, a2] })), v.payload, `carga ${v.id}`);
  }
});

test("a aprovação só vale para aquele documento: trocar qualquer campo muda o documento", async () => {
  const base = { chainId: "x", type: "cnh", id: "c1", subjectAddress: (await deriveAccount(vec.mnemonic, "t")).address, data: new Uint8Array([1, 2]), ref: "" };
  const d = hex(issueDoc(base));
  for (const change of [{ chainId: "y" }, { type: "id" }, { id: "c2" }, { data: new Uint8Array([1, 3]) }, { ref: "r" }]) {
    assert.notEqual(hex(issueDoc({ ...base, ...change })), d, JSON.stringify(Object.keys(change)));
  }
  assert.notEqual(hex(issueDoc({ ...base, subjectAddress: (await deriveAccount(vec.mnemonic, "outro")).address })), d);
});

test("pedido de proposta ao nó: tipo 1 + campos", async () => {
  const subject = (await deriveAccount(vec.mnemonic, "t")).address;
  const body = proposalFields({ type: "cnh", id: "c1", subjectAddress: subject, data: new Uint8Array([9]) });
  assert.equal(body[0], 1);
  assert.ok(body.length > 40);
});

test("o texto que o membro lê traz os campos por extenso", () => {
  const t = describeIssue({ typeLabel: "CNH", id: "cnh-1", subjectAddress: "brdc1abc", dataText: "categoria=B", privacy: "public", ref: "", threshold: 2 }).join(" | ");
  assert.match(t, /Emitir a credencial "CNH" \(cnh-1\)/);
  assert.match(t, /Dados públicos: categoria=B/);
  assert.match(t, /Precisa de 2 assinaturas/);
  const priv = describeIssue({ typeLabel: "Casamento", id: "c", subjectAddress: "brdc1abc", dataText: "", privacy: "private", ref: "cas-a", threshold: 2 }).join(" | ");
  assert.match(priv, /só o compromisso/);
  assert.match(priv, /Referente à credencial cas-a/);
});
