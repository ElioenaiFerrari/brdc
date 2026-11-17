# ADR-0017 — Catálogo inicial de contratos entre partes

**Status:** Aceito (dono do produto, 2026-11-17) · Fecha a pendência P5.

## Contexto
Os contratos entre partes são **modelos declarativos de máquina de estado** ([ADR-0004](0004-native-contracts-and-declarative-templates.md)): partes, assinaturas, condições, prazos e pagamentos em BRDC, sem código de terceiros. Falta dizer **quais** modelos existem no início.

## Decisão
Três modelos iniciais, todos com pagamento em BRDC e prazos em segundos ([ADR-0016](0016-block-time-and-windows-in-seconds.md)):
1. **Compra e venda** de um bem: o comprador deposita o valor em escrow, o vendedor aceita, o bem é transferido e o valor liberado; se o prazo vence sem conclusão, o escrow volta ao comprador.
2. **Aluguel:** locador e locatário assinam; caução em escrow; parcelas periódicas pagas pelo locatário; encerramento com devolução da caução (ou da parte que couber, conforme o acordo).
3. **Empréstimo simples:** credor entrega o valor, devedor devolve o principal até o prazo; **sem juros automáticos** nesta fase (juros viram parte do valor combinado).

Cada modelo é dado (estados, transições, quem assina cada uma, valores e prazos), validado ao ser criado. Só são possíveis as transições do modelo.

## Consequências e limites honestos
- **Sem arbitragem:** se as partes discordarem, a chain não decide quem tem razão; só executa as transições que ambas as partes assinaram. Disputa é fora da chain.
- Sem juros, correção monetária, multas automáticas nem oráculos. Podem entrar como modelos novos por ADR.
- Um contrato **não substitui** o contrato jurídico; é a execução automática do que as partes combinaram.
