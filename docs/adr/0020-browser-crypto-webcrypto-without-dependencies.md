# ADR-0020 — Criptografia do navegador: WebCrypto e código próprio, sem dependências

**Status:** Aceito (dono do produto, 2026-11-17) · Fecha a parte do navegador da pendência P6 · Complementa o [ADR-0006](0006-web-wallet-liveview-and-browser-crypto.md).

## Contexto
A carteira de autocustódia deriva chaves e assina **no navegador** ([ADR-0006](0006-web-wallet-liveview-and-browser-crypto.md)). Todas as bibliotecas JS de criptografia mais usadas (`@noble/hashes`, `@noble/curves`, `@scure/*`) têm **um único mantenedor** no npm. O dono do produto já recusou esse critério no canal P2P ([ADR-0015](0015-p2p-over-mutual-tls-1-3.md)). Além disso, cada pacote em uma carteira é superfície de **cadeia de suprimentos** (um pacote adulterado vê a frase).

Fatos verificados em 2026-11-17: o WebCrypto **nativo** tem Ed25519 (Chrome 137, Firefox 129, Safari 17), PBKDF2, HMAC, SHA-256/512 e AES-GCM; **não tem SHA-3**, que a BRDC usa no hash etiquetado e no endereço.

## Decisão
1. **Nenhuma dependência npm em tempo de execução na carteira.** Primitivas vêm do `crypto.subtle` do navegador: **Ed25519** (assinar e conferir), **PBKDF2-HMAC-SHA512** (BIP-39), **HMAC-SHA512** (SLIP-10), **SHA-256** (checksum do BIP-39), **AES-256-GCM** e **PBKDF2-SHA256** (cofre, [P: passphrase no cofre fica para a Fase 6]).
2. **Código próprio e pequeno** só para o que o navegador não tem, cada peça com vetores oficiais:
   - **SHA3-256** (Keccak, ~50 linhas);
   - **bech32m** (endereço `brdc1…`);
   - **BIP-39** (lista de palavras, checksum) e **SLIP-10** (derivação endurecida);
   - **codificação determinística** (ADR-0011) e montagem da transação.
3. **Chave de assinatura não extraível:** depois de derivada, a semente é importada no WebCrypto como `CryptoKey` **não extraível** (PKCS8), e a semente é apagada da memória JS (no melhor esforço). Assinar passa a ser pedir ao navegador.
4. **Prova de concordância com o nó:** os mesmos vetores (`vectors/crypto.json`) e um teste de **concordância em massa** (entradas aleatórias e todos os tamanhos de 0 a 600 bytes nas bordas de bloco) entre o JS e o Elixir, rodando no `mix brdc.check`. Uma divergência em hash ou assinatura aparece como "assinatura inválida" no nó.
5. **Navegadores mínimos:** Chrome 137, Firefox 129, Safari 17. Sem fallback em JS para Ed25519: navegador antigo recebe um aviso claro.
6. **Se um dia precisarmos de Argon2id** (melhor KDF para o cofre) ou de outro primitivo, a decisão volta por ADR, com a justificativa de cadeia de suprimentos.

## Evidência (teste prévio)
Um SHA3-256 próprio de 50 linhas passou nos vetores NIST (`""`, `"abc"`) e teve **0 divergências em 2.404 entradas** comparadas com o do Node (todos os tamanhos de 0 a 600 bytes). Custo: cerca de 0,1 ms por hash de 200 bytes.

## Alternativas
- `@noble/*` e `@scure/*`: bem auditadas e muito usadas (centenas de milhões de downloads por semana), mas **um só mantenedor** e mais superfície de pacote (descartadas pelo critério do dono).
- `libsodium-wrappers`: também um mantenedor, e WASM grande.
- `tweetnacl`: parada desde 2020.
- Trocar SHA3-256 por SHA-256 (nativo): exigiria mudar o ADR-0011 e a chain inteira só para evitar 50 linhas (descartada).

## Consequências e limites honestos
- **Criptografia de glue é nossa:** o risco é erro nosso, mitigado por vetores oficiais e pela concordância em massa com o Elixir. Os primitivos de verdade (Ed25519, AES, PBKDF2, HMAC) são do navegador.
- **SHA3-256 próprio não tem auditoria externa** e roda em BigInt (mais lento que bibliotecas otimizadas; irrelevante para o volume de uma carteira).
- **Não extraível** protege contra ler a chave, **não** contra assinar: XSS ou extensão maliciosa com a carteira destravada ainda pode assinar (limite de toda carteira quente).
- Dependemos do navegador para o Ed25519: uma falha do navegador é nossa falha.
- Sem zeroização garantida de memória em JS (o coletor de lixo decide).
- **A página também roda JavaScript de terceiros que não é criptografia:** o cliente do Phoenix LiveView (`phoenix`, `phoenix_live_view`, pacotes do Hex, mantidos por várias pessoas) e o `topbar` (barra de progresso). Eles ficam no **mesmo contexto** da criptografia: um defeito ou adulteração neles poderia assinar. Mitigações: versões fixas no `mix.lock`, CSP estrita, nenhum outro script. **Passo futuro** a avaliar: isolar a assinatura num `iframe` de outra origem ou num Worker, para que o código de interface não tenha acesso a ela.
- **Ferramentas de build** (esbuild, Tailwind, daisyUI e Heroicons, baixados no `mix setup` e só usados para gerar CSS e empacotar o JS): são de desenvolvimento e não rodam no navegador. O pacote do Hex `heroicons` e o `daisyui` vêm de repositórios do GitHub com versão fixa (`tag`) no `mix.exs`.
