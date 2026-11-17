// Bech32m (BIP-350): texto com prefixo legível e checksum. Usado nos endereços brdc1…
const CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
const GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
const CONST = 0x2bc830a3;

function polymod(values) {
  let chk = 1;
  for (const v of values) {
    const top = chk >>> 25;
    chk = (((chk & 0x1ffffff) << 5) ^ v) >>> 0;
    for (let i = 0; i < 5; i++) if ((top >>> i) & 1) chk = (chk ^ GEN[i]) >>> 0;
  }
  return chk;
}

const hrpExpand = (hrp) => [...hrp].map((c) => c.charCodeAt(0) >> 5).concat([0], [...hrp].map((c) => c.charCodeAt(0) & 31));

function toFive(bytes) {
  const bits = [];
  for (const b of bytes) for (let i = 7; i >= 0; i--) bits.push((b >> i) & 1);
  while (bits.length % 5) bits.push(0);
  const out = [];
  for (let i = 0; i < bits.length; i += 5) out.push(bits.slice(i, i + 5).reduce((a, b) => a * 2 + b, 0));
  return out;
}

function fromFive(values) {
  const bits = [];
  for (const v of values) for (let i = 4; i >= 0; i--) bits.push((v >> i) & 1);
  const pad = bits.length % 8;
  const body = bits.slice(0, bits.length - pad);
  if (pad > 4 || bits.slice(bits.length - pad).some((b) => b !== 0)) return null;
  const out = new Uint8Array(body.length / 8);
  for (let i = 0; i < out.length; i++) out[i] = body.slice(i * 8, i * 8 + 8).reduce((a, b) => a * 2 + b, 0);
  return out;
}

export function encode(hrp, bytes) {
  const five = toFive(bytes);
  const pm = (polymod([...hrpExpand(hrp), ...five, 0, 0, 0, 0, 0, 0]) ^ CONST) >>> 0;
  const check = [0, 1, 2, 3, 4, 5].map((i) => (pm >>> (5 * (5 - i))) & 31);
  return hrp + "1" + [...five, ...check].map((v) => CHARSET[v]).join("");
}

/** Devolve `{ hrp, bytes }` ou lança erro (checksum, caixa mista, caractere inválido…). */
export function decode(text) {
  if (text !== text.toLowerCase() && text !== text.toUpperCase()) throw new Error("caixa mista");
  const s = text.toLowerCase();
  const pos = s.lastIndexOf("1");
  if (pos < 1) throw new Error("sem separador ou prefixo vazio");
  const hrp = s.slice(0, pos);
  const values = [...s.slice(pos + 1)].map((c) => {
    const i = CHARSET.indexOf(c);
    if (i < 0) throw new Error("caractere inválido");
    return i;
  });
  if (values.length < 6) throw new Error("curto demais");
  if (polymod([...hrpExpand(hrp), ...values]) !== CONST) throw new Error("checksum inválido");
  const bytes = fromFive(values.slice(0, -6));
  if (!bytes) throw new Error("preenchimento inválido");
  return { hrp, bytes };
}
