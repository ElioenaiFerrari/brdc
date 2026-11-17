# Como ler o código da Fase 6, parte da criptografia do navegador

Pré-requisito: [Carteira HD e passphrase](03-hd-wallet-and-passphrase.md) e [Como ler a Fase 1](10-reading-phase-1-code.md). Fluxo: [Fluxo 12](../flows/12-browser-signing.md). Tudo em `apps/brdc_web/assets/js/crypto/`.

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `subtle.mjs` | acesso único ao `crypto.subtle` (igual no navegador e no Node 24) |
| 2 | `bytes.mjs` | hex, concatenação, inteiros de tamanho fixo e a codificação determinística (ADR-0011) |
| 3 | `keccak.mjs` | **SHA3-256 próprio** (50 linhas): o único primitivo que o navegador não tem |
| 4 | `hash.mjs` | hash etiquetado: `SHA3-256(tamanho da etiqueta ‖ etiqueta ‖ dados)` |
| 5 | `bech32m.mjs` | endereço com prefixo legível e checksum |
| 6 | `bip39.mjs` + `bip39_wordlist.mjs` | frase ↔ entropia ↔ semente, com passphrase |
| 7 | `slip10.mjs` | derivação endurecida (Ed25519) |
| 8 | `wallet.mjs` | conta: chave **não extraível** + endereço; assinar e conferir |
| 9 | `tx.mjs` | monta a transação com os mesmos bytes do Elixir e assina |

## Ideias-chave
- **Zero dependências npm:** tudo é do WebCrypto ou nosso, para não depender de um pacote que veria a frase.
- **A prova é a concordância:** `vectors/*.json` são gerados pelo **Elixir** e o JS tem de reproduzi-los byte a byte.
- **Não extraível:** depois de importada, a chave só assina; nem o nosso JS consegue lê-la.
- **Inteiros grandes:** valores até 2⁶⁴−1 exigem `BigInt` ou texto.

## Rode você mesmo
`make js-test` (18 testes). Para regerar os vetores do Elixir: `mix run --no-start tools/gen_wallet_vectors.exs`.

## Limites honestos
Veja o [Fluxo 12](../flows/12-browser-signing.md): ainda sem telas, sem cofre cifrado, só transferências nos vetores.
