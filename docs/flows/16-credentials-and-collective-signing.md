# Fluxo 16 — Credenciais e assinatura coletiva dos órgãos

> Diagrama: **a gerar** (adiado pelo dono; foco na implementação).

## Resumo
Um órgão (M de N membros) emite credenciais (CNH, identificação, casamento, divórcio). Um membro **propõe**; os outros **leem por extenso e assinam** cada um na sua carteira; com M assinaturas, qualquer membro **emite** pela transação tipo 15. O titular vê a credencial **pendente** e pode **contestá-la** durante a janela; depois, ela **ativa**.

## Quem participa
- **Membros do órgão** (cada um na própria carteira), **titular** da credencial, **autoridades raiz** (criam o tipo e o órgão; na rede de teste: `mix brdc.type`).
- **Servidor da carteira:** repassa propostas e aprovações ao nó e empurra ao navegador credenciais, tipos e propostas. Não vê chave nem frase.
- **Navegador (`registry_hook.js`, `crypto/proposals.mjs`):** mostra, recalcula o documento, assina.
- **Nó (`BrdcNode.Proposals`):** guarda propostas e confere aprovações; o ledger (`Credentials`) executa.

## Passo a passo
1. Autoridades criam o tipo com o órgão (`mix brdc.type cnh --organ <chave pública hex> …`).
2. Membro A: **Nova emissão** → tipo, endereço do titular, dados. Em tipo privado, um sal é gerado e só o **compromisso** vai à rede (A entrega dados e sal ao titular por fora).
3. Nó confere os campos (tipo, id livre, formato) e guarda a proposta.
4. Membro B vê a proposta, **lê os campos**, assina (`chave ‖ assinatura`); o nó confere contra o órgão.
5. Com M aprovações aparece **Emitir na rede**: tx tipo 15 com as aprovações; o ledger exige M.
6. Titular vê **Pendente: contestação até …**; **Contestar** (tx 16) ou, passada a janela, **Ativar** (tx 18).

## O que é verificado e por quem
Campos válidos: nó e ledger. Aprovações: nó (ao receber) e ledger (ao executar). Documento: recalculado por cada membro e pelo nó. Só o titular contesta; só dentro da janela.

## O que pode dar errado
Nó some com a proposta (propor de novo); membro assina sem ler (T20); saldo insuficiente para a taxa; id já usado; janela fechada.

## Onde está no código
`apps/brdc_node/lib/brdc_node/{proposals,handler,client,node}.ex`, `apps/brdc_ledger/lib/brdc_ledger/credentials.ex` (`check_issue/6`), `apps/brdc_web/assets/js/{registry_hook.js,crypto/proposals.mjs}`, `apps/brdc_dev/lib/brdc_dev/authority.ex`.

## Testes que cobrem
`proposals_test.exs` (8), `devnet_e2e_test.exs` (ciclo pela rede em TCP), `proposals.test.mjs` (4, bytes iguais aos do Elixir).

## Limites honestos
- **Verificado à mão no Chrome** com um órgão 2 de 3 (membros `m1` e `m2`, carteiras de passphrases diferentes em origens diferentes) e um titular: propor, duas assinaturas, emitir (taxa 0,01 cobrada), ver **Pendente**, esperar a janela e **Ativar**; a CNH ficou **Ativa**. O fluxo de **contestar** não foi repetido à mão (coberto por testes). O log do servidor só mostra os eventos `wallet:*` e `org:*`, sem frase, senha ou passphrase.
- Sem blocos vazios, o horário do último bloco fica parado: o nó confere as transações no horário do **próximo** bloco (relógio) e a tela usa o relógio para saber se a janela passou. O teste manual achou esse defeito (a janela nunca "vencia"); corrigido e coberto por teste.
- Só **emissão** tem proposta; veto, revogação e **bens** ainda usam transação direta (sem tela).
- Propostas ficam em memória do nó (somem no reinício).
- Tipos privados: a entrega de dados e sal ao titular é por fora da rede.
