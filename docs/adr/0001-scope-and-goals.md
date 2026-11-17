# ADR-0001 — Objetivo e escopo da BRDC

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
Queremos uma **cripto brasileira estilo USDC/USDT**, com contratos inteligentes que cobrem o que importa no dia a dia: transferência de propriedade, credenciais (CNH, identificação, casamento, divórcio…) e contratos entre partes. É um projeto de estudo: o dono quer **entender tudo**.

## Decisão
- A BRDC é uma **stablecoin em reais** (1 BRDC = 1 BRL) numa **blockchain própria em Elixir**, com **contratos nativos** e rede **P2P**.
- **Fora do escopo por ora:** votos e eleições (existem no projeto irmão Teko), integração bancária real (Pix/custódia), validade jurídica, hardware wallet, extensão de navegador e validadores abertos.
- A documentação é parte da entrega de cada fase (regra no `CLAUDE.md`).

## Consequências
O desenho prioriza clareza e verificabilidade sobre desempenho máximo. Todas as escolhas de segurança viram ADR.

## Limites honestos
Protótipo: sem auditoria, sem validade jurídica, sem integração bancária.
