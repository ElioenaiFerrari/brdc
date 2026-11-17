# ADR-0008 — Taxas pagas em BRDC

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
Toda rede precisa de uma defesa contra spam e de um incentivo a validar. Opções: **taxa em BRDC repartida entre validadores**; taxa zero; token nativo separado só para gás.

## Decisão
Cada transação paga uma **taxa em BRDC** (por byte e por tipo), repartida entre os validadores (proponente e votantes, regra a definir). **Não há moeda nativa volátil.**

## Alternativas descartadas
Taxa zero (sem proteção natural contra spam e sem incentivo); token de gás separado (quebra a ideia de "tudo em reais" e acrescenta complexidade regulatória e de produto).

## Consequências
- Custo previsível em reais; todo usuário precisa ter algum saldo em BRDC para transacionar.
- **Pendente:** tabela de taxas e a regra de repartição.
