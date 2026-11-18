# Como ler o código da Fase 6, parte do cofre e das telas de carteira

Pré-requisito: [Como ler a criptografia do navegador](16-reading-phase-6a-code.md). Fluxo: [Fluxo 13](../flows/13-wallet-vault.md).

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `assets/js/crypto/vault.mjs` | o cofre: AES-GCM + PBKDF2, parâmetros autenticados, recusa de rebaixamento |
| 2 | `assets/js/crypto/store.mjs` | onde o cofre mora: IndexedDB (navegador) ou memória (testes) |
| 3 | `assets/js/crypto/session.mjs` | criar, importar, destravar, bloquear, bloqueio por inatividade; a conta só vive aqui |
| 4 | `assets/js/vault_hook.js` | as telas: lê e limpa os campos, fala com o servidor só o endereço |
| 5 | `lib/.../vault_components.ex` | marcação estática do painel (sem segredo, sem `phx-change`) |
| 6 | `lib/.../live/wallet_live.ex` | o lado do servidor: só `wallet:unlocked` e `wallet:locked` |

## Ideias-chave
- **O servidor é espectador:** o painel é `phx-update="ignore"` e os campos não pertencem ao LiveView; o único dado que sobe é o endereço.
- **Passphrase fora do cofre** ([ADR-0021](../adr/0021-vault-never-stores-passphrase.md)): digitada a cada vez, usada e descartada.
- **Parâmetros como dado autenticado (AAD):** trocar o número de voltas não "abaixa a barra"; o cofre falha.
- **Limpeza ativa:** ao sair de uma tela, os campos e a lista de palavras são esvaziados.

## Rode você mesmo
`mix brdc.js.test` (30 testes). Para ver a tela: `mix phx.server` em `apps/brdc_web` e abra `http://localhost:4000/` (a carteira) ou `/design` (pré-visualização).

## Limites honestos
Veja o [Fluxo 13](../flows/13-wallet-vault.md): o hook e o IndexedDB foram verificados à mão, não por teste automatizado.
