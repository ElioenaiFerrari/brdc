# Como ler o código da Fase 5, parte de bens (`brdc_ledger`)

Pré-requisito: [Credenciais e bens](08-credentials-and-assets.md) e [Como ler o código da Fase 2](11-reading-phase-2-code.md). Fluxo com diagrama: [Fluxo 09](../flows/09-asset-trade.md).

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `approvals.ex` | aprovação M-de-N genérica: `chave ‖ assinatura` conta uma vez por chave distinta do conjunto autorizado |
| 2 | `assets.ex` | as 9 operações de bens (tipos 5 a 13), os documentos que o órgão assina e as cargas |
| 3 | `state.ex` | acrescenta `classes`, `assets`, `deals` e `escrow`, todos na raiz de estado |
| 4 | `executor.ex` | roteia os tipos 5 a 13 para `Assets` e cobra a taxa mínima |

## Ideias-chave
- **Quem manda em quê:** emissores cuidam da moeda; **autoridades raiz** criam classes; o **órgão da classe** cuida dos bens daquela classe. Três papéis separados.
- **Escrow é saldo "em suspensão":** sai da conta do comprador e fica em `state.escrow` até a finalização ou o veto. Por isso `saldos + escrow` é a oferta em circulação (`State.total_held/1`).
- **Janela por tempo, não por blocos:** `prazo = horário do bloco + janela`; veto só antes, finalização só depois ([ADR-0016](../adr/0016-block-time-and-windows-in-seconds.md)).
- **Revisão (`rev`):** impede reaproveitar uma aprovação do órgão. Se um veto ou gravame for aprovado e executado, `rev` sobe e a mesma aprovação não serve de novo.

## Rode você mesmo
Os testes são a melhor demonstração (`mix test apps/brdc_ledger/test/brdc_ledger/assets_test.exs`): o `world/0` monta uma classe, registra uma casa e cria dois compradores, e cada teste percorre um caminho (finalizar, vetar, gravame).

## Limites honestos
Veja o [Fluxo 09](../flows/09-asset-trade.md): o órgão é a fonte de verdade, sem arbitragem; credenciais e contratos entre partes ainda vêm.
