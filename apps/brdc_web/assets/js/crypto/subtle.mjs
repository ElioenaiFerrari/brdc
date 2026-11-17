// Acesso único ao WebCrypto: no navegador e no Node 24 é o mesmo `crypto.subtle`.
export const subtle = globalThis.crypto.subtle;
export const getRandomValues = (a) => globalThis.crypto.getRandomValues(a);
