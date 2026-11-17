// Onde o cofre mora. O registro é só texto hexadecimal cifrado: pode ficar em IndexedDB (navegador),
// ser exportado como backup ou, nos testes, ficar em memória.

/** Armazenamento em memória (testes). */
export function memoryStore() {
  let value = null;
  return {
    async get() {
      return value === null ? null : structuredClone(value);
    },
    async put(rec) {
      value = structuredClone(rec);
    },
    async clear() {
      value = null;
    },
  };
}

/** IndexedDB (navegador). Um único registro por origem. */
export function indexedDbStore({ dbName = "brdc-wallet", storeName = "vault", key = "main" } = {}) {
  const open = () =>
    new Promise((resolve, reject) => {
      const req = globalThis.indexedDB.open(dbName, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(storeName);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });

  const run = async (mode, fn) => {
    const db = await open();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, mode);
        const req = fn(tx.objectStore(storeName));
        tx.oncomplete = () => resolve(req?.result ?? null);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } finally {
      db.close();
    }
  };

  return {
    get: () => run("readonly", (s) => s.get(key)),
    put: (rec) => run("readwrite", (s) => s.put(rec, key)),
    clear: () => run("readwrite", (s) => s.delete(key)),
  };
}
