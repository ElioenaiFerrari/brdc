// Bens no navegador (ADR-0018): oferta, aceite, cancelamento e finalização. Cargas IGUAIS às do Elixir
// (vetores). A parte do órgão (registro, veto, gravame) usa as assinaturas coletivas e vem em outra etapa.
import { concat, fixed, stringField, bytesField, u32, u64 } from "./bytes.mjs";
import { tagged } from "./hash.mjs";
import { decodeAddress } from "./wallet.mjs";
import { proposalBody } from "./proposals.mjs";

export const KIND_OFFER = 7;
export const KIND_ACCEPT = 8;
export const KIND_CANCEL = 9;
export const KIND_FINALIZE = 11;

/** Oferta de venda: [bem, comprador (32), preço u64]. */
export const offerPayload = ({ asset, buyerAddress, price }) =>
  concat(stringField(asset), fixed(decodeAddress(buyerAddress), 32), u64(BigInt(price)));

/** Aceite, cancelamento e finalização carregam só o id do bem. */
export const assetPayload = (asset) => stringField(asset);

/** O que cada passo faz, em português, para a tela de revisão. `fmt` formata unidades em BRDC. */
export function describeStep(step, { asset, price, other, vetoWindow, fmt }) {
  const mins = (s) => (Number(s) >= 120 ? `${Math.round(Number(s) / 60)} minutos` : `${s} segundos`);
  switch (step) {
    case "offer":
      return [
        [`Oferecer o bem "${asset}" à venda`, "O que você está fazendo"],
        [`Para o comprador ${other}, por ${fmt(price)} BRDC`, "Condições"],
        ["Nada sai da sua conta agora. Você pode cancelar enquanto o comprador não aceitar.", "O que acontece"],
      ];
    case "accept":
      return [
        [`Aceitar a compra do bem "${asset}"`, "O que você está fazendo"],
        [`${fmt(price)} BRDC saem da sua conta e ficam retidos pela rede (escrow)`, "Dinheiro"],
        [`Durante ${mins(vetoWindow)} o órgão da classe pode vetar a venda (o dinheiro volta para você). Passado o prazo, a venda pode ser finalizada.`, "O que acontece"],
      ];
    case "cancel":
      return [
        [`Cancelar a oferta do bem "${asset}"`, "O que você está fazendo"],
        ["A oferta some. Só é possível antes de o comprador aceitar.", "O que acontece"],
      ];
    case "finalize":
      return [
        [`Finalizar a venda do bem "${asset}"`, "O que você está fazendo"],
        [`O bem passa ao comprador e ${fmt(price)} BRDC vão ao vendedor`, "O que acontece"],
        ["Qualquer uma das partes pode finalizar depois da janela de veto. Bem com gravame não é finalizado.", "Atenção"],
      ];
    default:
      return [];
  }
}

// --- ações do órgão (assinatura coletiva): documentos, cargas e campos das propostas, iguais aos do Elixir ---

export const KIND_REGISTER = 6;
export const KIND_VETO = 10;
export const KIND_LIEN_ADD = 12;
export const KIND_LIEN_REMOVE = 13;

const asset = (op, body) => tagged(`brdc/asset/${op}`, body);
const approvalsList = (list) => concat(u32(list.length), ...list.map((a) => bytesField(a)));

export const registerDoc = ({ chainId, cls, assetId, ownerAddress, meta }) =>
  asset("register", concat(stringField(chainId), stringField(cls), stringField(assetId), fixed(decodeAddress(ownerAddress), 32), bytesField(meta)));

export const vetoDoc = ({ chainId, assetId, rev, buyerAddress, price, deadline }) =>
  asset("veto", concat(stringField(chainId), stringField(assetId), u64(BigInt(rev)), fixed(decodeAddress(buyerAddress), 32), u64(BigInt(price)), u64(BigInt(deadline))));

export const lienAddDoc = ({ chainId, assetId, rev, lien, ref }) =>
  asset("lien_add", concat(stringField(chainId), stringField(assetId), u64(BigInt(rev)), stringField(lien), stringField(ref)));

export const lienRemoveDoc = ({ chainId, assetId, rev, lien, ref }) =>
  asset("lien_remove", concat(stringField(chainId), stringField(assetId), u64(BigInt(rev)), stringField(lien), stringField(ref)));

export const registerPayload = ({ cls, assetId, ownerAddress, meta, approvals }) =>
  concat(stringField(cls), stringField(assetId), fixed(decodeAddress(ownerAddress), 32), bytesField(meta), approvalsList(approvals));

export const vetoPayload = ({ assetId, approvals }) => concat(stringField(assetId), approvalsList(approvals));

export const lienAddPayload = ({ assetId, lien, ref, approvals }) =>
  concat(stringField(assetId), stringField(lien), stringField(ref), approvalsList(approvals));

export const lienRemovePayload = ({ assetId, lien, approvals }) => concat(stringField(assetId), stringField(lien), approvalsList(approvals));

/** Corpos dos pedidos de proposta (campos por tipo; o nó recalcula o resto do estado). */
export const registerProposal = ({ cls, assetId, ownerAddress, meta }) =>
  proposalBody("asset_register", concat(stringField(cls), stringField(assetId), fixed(decodeAddress(ownerAddress), 32), bytesField(meta)));
export const vetoProposal = ({ assetId }) => proposalBody("asset_veto", stringField(assetId));
export const lienAddProposal = ({ assetId, lien, ref }) => proposalBody("lien_add", concat(stringField(assetId), stringField(lien), stringField(ref)));
export const lienRemoveProposal = ({ assetId, lien }) => proposalBody("lien_remove", concat(stringField(assetId), stringField(lien)));

/** O que o membro do órgão lê antes de assinar, em português. */
export function describeOrganAction(op, { assetId, cls, ownerAddress, metaText, buyerAddress, price, lien, ref, threshold, fmt }) {
  const need = `Precisa de ${threshold} assinaturas do órgão da classe.`;
  switch (op) {
    case "asset_register":
      return [`Registrar o bem "${assetId}" na classe "${cls}"`, `Dono: ${ownerAddress}`, `Descrição: ${metaText}`, need];
    case "asset_veto":
      return [`Vetar a venda do bem "${assetId}"`, `Comprador: ${buyerAddress}, preço ${fmt(price)} BRDC`, "O veto cancela a negociação e devolve o dinheiro retido ao comprador.", need];
    case "lien_add":
      return [`Adicionar o gravame "${lien}" ao bem "${assetId}"`, `Referência: ${ref}`, "Enquanto houver gravame, o bem não pode ser vendido.", need];
    case "lien_remove":
      return [`Remover o gravame "${lien}" do bem "${assetId}"`, `Referência: ${ref}`, need];
    default:
      return [];
  }
}
