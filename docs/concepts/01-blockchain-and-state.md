# 1. Blockchain e estado

## O que é
Uma **blockchain** é um registro compartilhado e **só de acrescentar** (append-only). As entradas são agrupadas em **blocos**; cada bloco carrega o **hash** do anterior, formando uma corrente: alterar um bloco antigo mudaria o hash dele e quebraria todos os seguintes.

Mas o que interessa para uma moeda não é a lista de blocos e sim o **estado**: "quanto cada endereço tem agora". O estado é o resultado de aplicar, em ordem, todas as transações de todos os blocos.

## Como funciona (ideia)
```
estado_0 --(bloco 1)--> estado_1 --(bloco 2)--> estado_2 ...
```
Um **ledger** (livro-razão) é essa função: `aplicar(estado, bloco) -> novo_estado`.

Ilustrativo (ainda não existe no código):
```elixir
defmodule Ledger do
  def apply_block(state, block), do: Enum.reduce(block.txs, state, &apply_tx/2)
end
```

## Determinismo: a propriedade que sustenta tudo
Cada nó executa o bloco **por conta própria**. Para que todos cheguem ao mesmo estado, a execução precisa ser **determinística**: mesmo estado + mesmo bloco = mesmo resultado, em qualquer máquina, hoje ou daqui a um ano. Por isso, dentro da execução **não pode haver**: relógio do computador, números aleatórios, leitura de arquivo ou rede, ordem de iteração indefinida (mapas sem ordem), ponto flutuante.

O cabeçalho do bloco carrega a **raiz de estado** (um hash que resume o estado). Se dois nós executam o mesmo bloco e obtêm raízes diferentes, sabem imediatamente que há um bug ou um nó adulterado.

## Modelo de conta
Na BRDC cada **endereço** tem um **saldo** e um **nonce** (contador de transações enviadas). Transferir 10 BRDC de A para B debita A, credita B e incrementa o nonce de A. O nonce impede **replay** (reenviar a mesma transação) e fixa a ordem. (Proposta no [ADR-0010](../adr/0010-account-model-address-and-decimals.md).)

## Erros comuns
- Achar que a blockchain "guarda moedas": ela guarda **o estado** e as regras para mudá-lo.
- Usar `DateTime.utc_now()` ou `:rand` dentro da execução: dois nós divergem.

## Como a BRDC usa
Todo o estado (contas, bens, credenciais, contratos) vive na **árvore de estado** e é resumido pela raiz em cada bloco ([ADR-0012](../adr/0012-state-tree-and-storage.md)). O app `brdc_ledger` será puro: não conhece rede nem consenso.

## Onde está no código
*Planejado (Fase 2).*

## Para ir além
O [ARCHITECTURE](../ARCHITECTURE.md) mostra onde o ledger se encaixa.
