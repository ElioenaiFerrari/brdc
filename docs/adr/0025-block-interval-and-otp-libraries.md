# ADR-0025 — Intervalo entre blocos e bibliotecas OTP da Fase 7

**Status:** Aceito (dono do produto, 2026-11-17) · Resolve P3 e P7

## Decisão
1. **Blocos só quando há transação pendente**, depois de um **intervalo de agrupamento**: **1 s** na devnet e **2 s** na testnet. **Sem bloco vazio e sem batimento** (as janelas e prazos são avaliados no horário do próximo bloco, então o relógio basta).
2. **Teto por bloco:** 500 transações ou 256 KiB (o que vier primeiro). Valores **provisórios**, a medir na M2.
3. **Bibliotecas:** nenhuma nova na Fase 7. Só `GenServer`, `Registry`, `Task.Supervisor`, `:file` e `:telemetry` (já vem com o Phoenix, mantido por uma organização). GenStage, Broadway, Flow e Benchee só entram com **medição** que justifique e justificativa de supply chain própria.

## Consequências
Latência de inclusão de cerca de 1 a 2 s mais o tempo do consenso; rede ociosa não gera blocos.
