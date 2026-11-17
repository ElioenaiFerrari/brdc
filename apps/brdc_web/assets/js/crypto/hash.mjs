// Hash etiquetado da BRDC (ADR-0011): SHA3-256(tamanho da etiqueta (4 bytes) ‖ etiqueta ‖ dados).
import { sha3_256 } from "./keccak.mjs";
import { concat, u32, utf8 } from "./bytes.mjs";

export function tagged(tag, data) {
  const t = utf8(tag);
  return sha3_256(concat(u32(t.length), t, data));
}

export { sha3_256 };
