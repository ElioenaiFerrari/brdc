# ADR-0002 — Lastro em reais e emissores autorizados

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
Uma stablecoin precisa de um mecanismo que mantenha 1 BRDC = 1 BRL. Opções: (a) **lastro em reais** guardados por emissores/custodiantes (USDC, USDT); (b) **colateral em cripto** com liquidação automática (DAI); (c) **algorítmica**, sem lastro (UST, que colapsou).

## Decisão
**Lastro em reais, com emissores autorizados.** Um conjunto de emissores (decisão **M-de-N**, como os órgãos do Teko) **cria (mint)** BRDC quando recebe reais e **destrói (burn)** quando devolve reais. As reservas são **atestadas on-chain**: os emissores publicam, assinados, quanto há em reserva, e a chain mantém a invariante **oferta total = emitido − queimado**.

## Alternativas descartadas
Colateral em cripto (exige oráculos de preço, liquidações e é muito mais complexo e arriscado); algorítmica (historicamente instável).

## Consequências
- Mint e burn são transações privilegiadas, válidas só com M assinaturas distintas de emissores.
- A chain **não consegue provar** que os reais existem: prova só o que foi **atestado**. É o mesmo risco de confiança do USDC/USDT; a mitigação é transparência (atestados públicos, auditoria externa fora da chain).
- Quem são os emissores iniciais e como o conjunto muda é **decisão PENDENTE** (ver README dos ADRs).
