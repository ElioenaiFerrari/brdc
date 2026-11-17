// Bens no navegador (ADR-0018): oferta, aceite, cancelamento e finalização. Cargas IGUAIS às do Elixir
// (vetores). A parte do órgão (registro, veto, gravame) usa as assinaturas coletivas e vem em outra etapa.
import { concat, fixed, stringField, u64 } from "./bytes.mjs";
import { decodeAddress } from "./wallet.mjs";

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
