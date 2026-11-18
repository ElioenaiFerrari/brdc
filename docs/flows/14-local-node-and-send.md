# Fluxo 14 — Nó local, saldo e envio de BRDC pela carteira

## Resumo
A carteira mostra o saldo real e envia BRDC falando com um **nó** pela porta pública. A transação é **montada e assinada no navegador**, depois de mostrar em texto claro o que será assinado; o servidor da carteira só repassa os bytes ao nó, que a valida e a inclui no próximo bloco.

## Quem participa
- **Pessoa e navegador:** montam, mostram, assinam.
- **`WalletLive` (servidor da carteira):** cliente do nó (`BrdcWebWeb.Wallet.Chain` → `BrdcNode.Client`).
- **Nó local** (`BrdcNode.Node` + `BrdcP2p.PublicPort`): valida, guarda no mempool e produz blocos.
- **Ferramentas de desenvolvimento** (`brdc_dev`): `mix brdc.fund` (BRDC de teste) e `mix brdc.balance`.

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
**Subir:** `mix phx.server` (na raiz) sobe a carteira (`http://localhost:4000`) e o nó local (porta 4545, rede `brdc-devnet`). Na primeira vez as chaves e a gênese são criadas em `net/` (fora do git, sementes `0600`).

**Financiar (teste):** `mix brdc.fund brdc1… 100` assina como os dois emissores de teste (2 de 2) e envia o mint ao nó pela porta pública; o saldo aparece no próximo bloco.

**Saldo:** ao destravar, o servidor consulta status e conta no nó e atualiza sozinho (a cada 1 s com transação pendente, a cada 5 s sem). Mostra saldo, pendente e `rede · bloco`.

**Enviar**
1. A pessoa informa o endereço de destino (validado pelo checksum) e o valor. **O campo de valor tem máscara pt-BR** (`1.234,56`: milhares com ponto, vírgula decimal, até 6 casas, cursor preservado). **Um ponto digitado vira a vírgula decimal** (digitar `1250.5` dá `1.250,5`, nunca 12.505); vírgula e ponto a mais são ignorados; o que se cola (`R$ 10,50`, `10.50`, `1,234.56`) é normalizado. O parser estrito continua valendo por baixo (`1.5` colado cru nunca vira 15).
2. O navegador pede ao servidor os **dados públicos** (`wallet:prepare`: rede, nonce, saldo, tabela de taxas) e monta a transação com a **taxa mínima** (1000 + 1 por byte).
3. A tela **"Confira antes de assinar"** mostra valor, destino inteiro, taxa, total debitado e a rede (cada valor **se revela com o efeito de letras**, ver o [guia de design](../design/README.md)); avisa que transferências não podem ser desfeitas. Ao assinar, o botão mostra "Assinando e enviando…" cintilando até a rede responder.
4. Ao confirmar, a chave **não extraível** assina; o navegador envia **só a transação pronta** (`wallet:submit`).
5. O servidor confere que a transação é do endereço da carteira e a repassa ao nó. O nó valida (assinatura, nonce, saldo, taxa) contra o estado **com as pendentes** e responde com o id ou o motivo.
6. No próximo bloco o saldo muda; o validador recebe a taxa.

## O que é verificado e por quem
- **Navegador:** endereço (bech32m), valor (parser estrito), saldo suficiente (valor + taxa), o que vai ser assinado.
- **Servidor da carteira:** endereço do remetente igual ao da carteira; nada além disso (não tem segredo para conferir).
- **Nó:** `Executor.apply_tx` sobre o estado com as pendentes; duplicados, mempool cheio, limites de bloco.
- **Concordância JS/Elixir:** a taxa mínima do JS é a do Elixir (vetores); os bytes assinados são idênticos ([Fluxo 12](12-browser-signing.md)).

## O que pode dar errado
- **Nó mentiroso** (omite, atrasa, mostra saldo ou nonce falsos): saldo ou nonce errados só fazem a transação falhar; a **rede** e o **total** aparecem na revisão. Sem provas de estado ainda ([ADR-0023](../adr/0023-local-node-and-wallet-as-client.md)).
- **Sem conexão com o nó:** a carteira segue destravando e mostra "Sem conexão com a rede"; enviar fica indisponível.
- **Transferência para endereço errado (válido):** não há como desfazer ou bloquear (ADR-0009). Por isso a revisão mostra o endereço inteiro.
- **Nó local reiniciado:** o disco (`net/data`) guarda os blocos: ao subir, o nó relê e **reexecuta** o log (ADR-0012), então saldos, bens, credenciais e propostas continuam. Para recomeçar da gênese, pare o nó e rode `mix brdc.devnet.reset`. Verificado com `kill -9` do servidor.

## Onde está no código
`apps/brdc_node/lib/brdc_node/node.ex`, `handler.ex`, `client.ex`; `apps/brdc_dev/` (`devnet.ex`, `funding.ex`, `application.ex`, tarefas `brdc.fund` e `brdc.balance`); `apps/brdc_web/lib/brdc_web_web/wallet/chain.ex`, `live/wallet_live.ex`, `components/send_components.ex`; `apps/brdc_web/assets/js/send_hook.js` e `crypto/{send,amount}.mjs`; `apps/brdc_ledger/lib/brdc_ledger/amount.ex`.

## Testes que cobrem
`node_test.exs` (11: bloco só com pendente, saldo pendente x confirmado, recusas, nonce em sequência, horário que não decresce, assinantes, relógio automático, limite de transações por bloco, ponte da porta pública), `devnet_e2e_test.exs` (5, **pela rede em TCP**: financiar, bloco, saldo, transferência assinada pelo cliente, taxa ao validador), `wallet_node_test.exs` (6: saldo real, sem nó, `prepare`, `submit` e recusas, nada de segredo), `send.test.mjs` (5: parser estrito, texto, taxa igual à do Elixir, montagem), `amount_test.exs`. **Verificado à mão no Chrome 153**: criar, financiar, ver o saldo aparecer, enviar 12,5 BRDC, conferir destino e remetente no nó; o log do servidor só tem `unlocked`, `prepare` e `submit`.

## Limites honestos
- Só **transferências** pela tela; bens, contratos e credenciais ainda não têm tela.
- **Um validador**: o motor BFT e o P2P entre validadores não estão ligados a este nó.
- Sem histórico de transações na tela (o bloco ainda não tem codificação de rede).
- Intervalo de bloco fixo de 1 s em desenvolvimento (P3 pendente).
