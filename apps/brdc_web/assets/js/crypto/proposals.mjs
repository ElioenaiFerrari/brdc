// Assinatura coletiva dos órgãos no navegador (ADR-0019/0022). Cada membro assina o DOCUMENTO de uma emissão
// de credencial; com M aprovações, qualquer membro monta a transação. O documento é calculado aqui com a MESMA
// regra do Elixir (vetores conferem); o nó o recalcula e não confia no que recebe.
import { concat, fixed, stringField, bytesField, u32, u8 } from "./bytes.mjs";
import { tagged } from "./hash.mjs";
import { decodeAddress } from "./wallet.mjs";

export const KIND_ISSUE = 15;

/** Documento de emissão: hash etiquetado `brdc/cred/issue` de [rede, tipo, id, titular, dados, referência]. */
export function issueDoc({ chainId, type, id, subjectAddress, data, ref = "" }) {
  const body = concat(
    stringField(chainId),
    stringField(type),
    stringField(id),
    fixed(decodeAddress(subjectAddress), 32),
    bytesField(data),
    stringField(ref),
  );
  return tagged("brdc/cred/issue", body);
}

/** Aprovação de um membro: chave pública (32) ‖ assinatura (64) sobre o documento. */
export async function approve(account, doc) {
  return concat(account.publicKey, await account.sign(doc));
}

/** Carga da transação de emissão (tipo 15), com as aprovações reunidas. */
export function issuePayload({ type, id, subjectAddress, data, ref = "", approvals }) {
  return concat(
    stringField(type),
    stringField(id),
    fixed(decodeAddress(subjectAddress), 32),
    bytesField(data),
    stringField(ref),
    u32(approvals.length),
    ...approvals.map((a) => bytesField(a)),
  );
}

/** Números dos tipos de proposta na porta pública (iguais aos de `BrdcNode.Proposals`). */
export const KIND = { credential_issue: 1, asset_register: 2, asset_veto: 3, lien_add: 4, lien_remove: 5 };

/** Corpo do pedido de proposta ao nó: subtipo 1, número do tipo e os campos do tipo. */
export const proposalBody = (kind, fields) => concat(u8(1), u8(KIND[kind]), fields);

/** Campos da emissão de credencial (para `proposalBody`). */
export function proposalFields({ type, id, subjectAddress, data, ref = "" }) {
  return proposalBody(
    "credential_issue",
    concat(stringField(type), stringField(id), fixed(decodeAddress(subjectAddress), 32), bytesField(data), stringField(ref)),
  );
}

/** O que cada membro lê antes de assinar, em português. Nada de hash: os campos, escritos por extenso. */
export function describeIssue({ typeLabel, id, subjectAddress, dataText, privacy, ref, threshold }) {
  const lines = [
    `Emitir a credencial "${typeLabel}" (${id})`,
    `Para o titular ${subjectAddress}`,
    privacy === "private" ? "Credencial privada: só o compromisso (hash) dos dados fica na rede." : `Dados públicos: ${dataText}`,
  ];
  if (ref) lines.push(`Referente à credencial ${ref}`);
  lines.push(`Precisa de ${threshold} assinaturas do órgão. Depois emitida, ela fica pendente durante a janela de contestação.`);
  return lines;
}

export const KIND_CONTEST = 16;
export const KIND_ACTIVATE = 18;

/** Carga de contestar (16) ou ativar (18) uma credencial: só o id. */
export const idPayload = (id) => stringField(id);

/** Transação (ainda sem assinatura) com a taxa informada: usada pelos tipos de credencial. */
export function buildTx({ kind, chainId, nonce, fee, senderPublicKey, payload }) {
  return { chainId, kind, nonce: BigInt(nonce), fee: BigInt(fee), senderPublicKey, payload };
}

/** Compromisso de dados privados: hash etiquetado de sal (16 bytes) ‖ dados. O titular guarda os dados e o sal. */
export function commitment(salt, dataBytes) {
  return tagged("brdc/cred/commitment", concat(salt, dataBytes));
}

