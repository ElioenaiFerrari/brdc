// Transação da BRDC: bytes idênticos aos do Elixir (BrdcLedger.Tx). A assinatura cobre TUDO, inclusive
// o chain_id e o nonce.
import { concat, u8, u64, fixed, stringField, bytesField } from "./bytes.mjs";
import { tagged } from "./hash.mjs";
import { decodeAddress } from "./wallet.mjs";

export const KIND = Object.freeze({ transfer: 1, mint: 2, burn: 3, attestation: 4 });

/** Bytes assinados: tudo, menos a assinatura. */
export function signingBytes(tx) {
  return concat(
    stringField(tx.chainId),
    u8(tx.kind),
    u64(tx.nonce),
    u64(tx.fee),
    fixed(tx.senderPublicKey, 32),
    bytesField(tx.payload),
  );
}

/** Carga de transferência: endereço de destino (hash de 32 bytes) e valor em unidades mínimas. */
export function transferPayload(toAddress, amount) {
  if (BigInt(amount) <= 0n) throw new RangeError("valor deve ser positivo");
  return concat(fixed(decodeAddress(toAddress), 32), u64(amount));
}

/** Assina com a conta (`deriveAccount`). Devolve a transação com `signature`. */
export async function signTx(tx, account) {
  const signature = await account.sign(tagged("brdc/tx", signingBytes(tx)));
  return { ...tx, signature };
}

/** Codificação completa (com assinatura): é o que vai para a rede. */
export const encodeTx = (tx) => concat(signingBytes(tx), fixed(tx.signature, 64));

/** Identificador da transação. */
export const txId = (tx) => tagged("brdc/txid", encodeTx(tx));
