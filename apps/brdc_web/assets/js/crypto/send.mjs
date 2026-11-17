// Montagem da transferência no navegador: a taxa mínima (ADR-0014) e a transação a assinar.
import { KIND, signingBytes, transferPayload } from "./tx.mjs";

/** Taxa mínima de uma transferência: base + por byte do que vai pela rede (corpo assinado + 64 da assinatura). */
export const minFee = ({ transferBase, perByte }, tx) =>
  BigInt(transferBase) + BigInt(perByte) * BigInt(signingBytes(tx).length + 64);

/**
 * Monta a transferência (ainda sem assinatura) com a taxa mínima. O tamanho não depende do valor da taxa
 * (inteiros de tamanho fixo), então calcula-se com taxa 0 e depois preenche.
 * `info` = dados públicos da rede e da conta (do nó): { chainId, nonce, transferBase, perByte }.
 */
export function buildTransfer({ info, senderPublicKey, toAddress, amount }) {
  const base = {
    chainId: info.chainId,
    kind: KIND.transfer,
    nonce: BigInt(info.nonce),
    fee: 0n,
    senderPublicKey,
    payload: transferPayload(toAddress, BigInt(amount)),
  };
  const fee = minFee(info, base);
  return { tx: { ...base, fee }, fee, total: BigInt(amount) + fee };
}
