# ADR-0006 — Carteira web: LiveView e criptografia só no navegador

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
A carteira é web, não custodial (hot wallet estilo MetaMask/Proton). LiveView renderiza no servidor, o que **não pode** envolver chaves. Opções: LiveView + hooks JS; SPA falando JSON-RPC; extensão de navegador.

## Decisão
**LiveView para a casca** (telas, saldo, histórico, explorador, tempo real por PubSub) e **criptografia só no navegador**: geração da frase, derivação, cofre cifrado pela senha local (IndexedDB) e **assinatura** rodam em JavaScript (hooks). O servidor **nunca recebe** chave, frase ou passphrase; só transação já assinada. CSP estrita e **nenhum script de terceiros**.

## Alternativas descartadas
SPA (duplica o stack e perde o tempo real simples); extensão (isola melhor as chaves, mas custa mais; fica como fase futura).

## Consequências e limites
- Uma carteira quente no navegador é exposta a XSS, extensões maliciosas e malware: **não equivale a hardware wallet**. Um servidor adulterado poderia servir JS malicioso; CSP e integridade dos recursos reduzem o risco, não o eliminam.
- O JS e o Elixir precisam concordar byte a byte (vetores de teste compartilhados).
