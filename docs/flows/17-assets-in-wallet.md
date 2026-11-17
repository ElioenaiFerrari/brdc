# Fluxo 17 — Bens na carteira (dono e comprador)

> Diagrama: **a gerar** (adiado pelo dono; foco na implementação).

## Resumo
A carteira mostra os bens registrados em nome do usuário e os que ele está comprando, e opera a **negociação direta** do [ADR-0018](../adr/0018-assets-direct-trade-with-veto-window.md): o dono **oferece**, o comprador **aceita** (o preço fica retido na rede, em escrow), o órgão da classe pode **vetar** durante a janela, e depois dela qualquer parte **finaliza**. Cada passo é uma transação assinada no navegador, depois de uma tela que descreve por extenso o que acontece e quanto dinheiro se move.

## Quem participa
- **Dono** (vendedor) e **comprador**, cada um na própria carteira.
- **Órgão da classe** (M de N): registra o bem, veta vendas e põe ou tira gravames, **na própria carteira**, pelas assinaturas coletivas ([fluxo 16](16-credentials-and-collective-signing.md)). Na rede de teste, `mix brdc.asset` cria classes e pode registrar bens simulando o órgão.
- **Servidor da carteira:** pergunta ao nó os bens do endereço (consulta tipo 5, subtipo 4) e os empurra ao navegador.
- **Navegador (`assets_hook.js`, `crypto/assets.mjs`):** desenha, calcula o texto, assina.
- **Nó/ledger (`BrdcLedger.Assets`):** executa e valida.

## Passo a passo
1. (dev) `mix brdc.asset class imovel --organ <chave hex> --veto 20` e `mix brdc.asset register imovel casa-1 <endereço do dono> "descrição" --organ-test 1`.
2. **Oferecer à venda** (tx 7): comprador + preço. Nada sai da conta. O dono pode **cancelar** (tx 9) até o aceite.
3. **Aceitar e pagar** (tx 8, comprador): o preço sai do saldo e fica em escrow; começa a janela de veto da classe.
4. Dentro da janela, o órgão pode **vetar** (tx 10, por proposta e assinaturas): o dinheiro volta ao comprador. A tela do órgão mostra comprador e preço **tirados do estado**; passado o prazo, a proposta caduca.
5. Passada a janela, **Finalizar venda** (tx 11, qualquer parte): o bem passa ao comprador, o preço vai ao vendedor. Bem com gravame não finaliza.

## O que é verificado e por quem
Dono, estado da negociação, gravame, saldo e prazo: ledger (`Assets.run/4`). Texto da revisão: calculado no navegador a partir dos mesmos campos da transação. Taxa: `asset_step_fee`, vinda do status do nó.

## O que pode dar errado
Saldo insuficiente (preço + taxa no aceite); oferta para si mesmo; bem com gravame; finalizar antes do fim da janela (a tela só oferece o botão depois); veto do órgão.

## Onde está no código
`apps/brdc_node/lib/brdc_node/{node,handler,client}.ex` (`assets_of`), `apps/brdc_web/assets/js/{assets_hook.js,crypto/assets.mjs}`, `apps/brdc_dev/lib/brdc_dev/authority.ex` e `lib/mix/tasks/brdc.asset.ex`.

## Testes que cobrem
`proposals_assets_test.exs` (8: registro, veto, gravame, revisão antiga, caducidade, porta pública), `devnet_e2e_test.exs` (registro por proposta pela rede), `assets.test.mjs` (documento, aprovações e carga das 4 ações = Elixir). `assets.test.mjs` (3, cargas iguais às do Elixir), `devnet_e2e_test.exs` (ciclo completo pela rede: classe, registro, oferta, aceite com escrow, finalização por relógio). **Verificado à mão no Chrome** com vendedor e comprador em origens diferentes: oferta de 30 BRDC, aceite, espera da janela (20 s) e finalização; saldos fecharam (comprador 100 → 69,96; vendedor 10 → 39,98) e o bem passou ao comprador.

## Limites honestos
- **Criar a classe** ainda é das autoridades raiz (em dev, `mix brdc.asset class`); não há tela.
- Sem notificação à outra parte: ela vê a oferta quando abre a carteira.
- **Verificado à mão** também o lado do órgão: registro de bem por proposta (assinar e emitir, taxa 0,05), e **veto** de uma venda com 3 BRDC em escrow (o dinheiro voltou ao comprador, o bem saiu da lista). Adicionar e remover gravame só foram exercitados por testes e vetores (documento e carga iguais aos do Elixir). O teste manual achou que uma proposta de veto de janela vencida continuava listada; corrigido (a proposta caduca).
