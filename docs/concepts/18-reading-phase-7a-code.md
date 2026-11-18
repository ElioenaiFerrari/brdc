# Como ler o código do nó local e do envio de BRDC

Fluxo: [Fluxo 14](../flows/14-local-node-and-send.md). Decisão: [ADR-0023](../adr/0023-local-node-and-wallet-as-client.md).

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `brdc_node/lib/brdc_node/node.ex` | o nó: estado, mempool, produção de blocos, assinantes |
| 2 | `brdc_node/lib/brdc_node/handler.ex` | traduz os pedidos da porta pública (`status`, `get_account`, `submit_tx`) |
| 3 | `brdc_node/lib/brdc_node/client.ex` | o cliente: quem fala com um nó (carteira e ferramentas) |
| 4 | `brdc_web/lib/brdc_web_web/wallet/chain.ex` | a carteira como cliente: saldo e repasse de transações |
| 5 | `brdc_web/lib/brdc_web_web/live/wallet_live.ex` | os eventos `unlocked`, `locked`, `prepare`, `submit` |
| 6 | `brdc_web/assets/js/send_hook.js` + `crypto/send.mjs` | monta, mostra, assina e envia |
| 7 | `brdc_dev/` | nó de desenvolvimento, `mix brdc.fund`, `mix brdc.balance` |

## Ideias-chave
- **A carteira é cliente, não nó:** fala com o nó por TCP, mesmo na mesma máquina. Em produção o nó e o servidor da carteira são entregas separadas.
- **Estado "com pendentes":** o nó valida cada transação contra o estado como ficaria com as que já esperam; por isso duas transferências seguidas da mesma conta (nonces 0 e 1) entram.
- **Nunca bloco vazio:** o relógio só arma quando há pendente e desarma quando acaba.
- **A tela mostra o que será assinado:** quem assina vê valor, destino, taxa, total e rede em texto claro.

## Contratos na carteira
Fluxo [15](../flows/15-contracts-in-wallet.md): `crypto/contracts.mjs` (montar, avaliar efeitos), `contracts_hook.js` (a tela) e `contracts_ui.js` (textos em português). Os modelos vêm do Elixir em `generated/contract_templates.json`.

## Rode você mesmo
`mix phx.server`, abra `http://localhost:4000`, crie uma carteira, copie o endereço e rode `mix brdc.fund brdc1… 100`. Depois envie para outro endereço pela tela.

## Limites honestos
Veja o [Fluxo 14](../flows/14-local-node-and-send.md): um validador só, só transferências, sem histórico.
