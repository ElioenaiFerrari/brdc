# Como ler o código da Fase 5, parte de contratos (`brdc_ledger`)

Pré-requisito: [Contratos nativos](06-native-contracts.md). Fluxo com diagrama: [Fluxo 11](../flows/11-contracts.md).

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `contract_templates.ex` | os três modelos **como dados** e o vocabulário fechado documentado no `@moduledoc` |
| 2 | `contracts.ex` | o motor: cria, confere estado/ator/condições e aplica os efeitos |
| 3 | `state.ex` | acrescenta `contracts` (e a raiz) |

## Ideias-chave
- **Dado em vez de código:** adicionar um modelo é escrever um mapa em `contract_templates.ex`, sem tocar no motor, e um teste confere que ele só usa o que o motor conhece.
- **Tudo ou nada:** os efeitos rodam em ordem sobre cópias imutáveis do estado; se um falha (`:insufficient_funds`), o estado original continua intacto.
- **Escrow por contrato:** cada contrato guarda o seu `escrow`, e `state.escrow` é a soma de todos (bens e contratos). Estado final sem dinheiro retido.
- **Tempo do bloco:** condições `{:at_or_after, var}` comparam o horário do bloco com um prazo guardado em `vars`.

## Para ler um modelo
Abra `"aluguel"` em `contract_templates.ex`: `accept` trava a caução e calcula `settle_at`; `pay_rent` paga direto ao locador; `settle` libera `min(caução, parcelas em aberto × parcela)` ao locador e o resto ao locatário. Depois leia o teste `parcelas não pagas saem da caução` em `contracts_test.exs`.

## Limites honestos
Veja o [Fluxo 11](../flows/11-contracts.md): sem arbitragem, sem juros, sem rescisão antecipada do aluguel.
