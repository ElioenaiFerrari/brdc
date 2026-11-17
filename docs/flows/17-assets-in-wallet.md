# Fluxo 17 — Bens na carteira (dono e comprador)

> Diagrama: **a gerar** (adiado pelo dono; foco na implementação).

## Resumo
A carteira mostra os bens registrados em nome do usuário e os que ele está comprando, e opera a **negociação direta** do [ADR-0018](../adr/0018-assets-direct-trade-with-veto-window.md): o dono **oferece**, o comprador **aceita** (o preço fica retido na rede, em escrow), o órgão da classe pode **vetar** durante a janela, e depois dela qualquer parte **finaliza**. Cada passo é uma transação assinada no navegador, depois de uma tela que descreve por extenso o que acontece e quanto dinheiro se move.

## Quem participa
- **Dono** (vendedor) e **comprador**, cada um na própria carteira.
- **Órgão da classe** (M de N): registra o bem e pode vetar. **Ainda sem tela**; na rede de teste, `mix brdc.asset` simula as autoridades e o órgão.
- **Servidor da carteira:** pergunta ao nó os bens do endereço (consulta tipo 5, subtipo 4) e os empurra ao navegador.
- **Navegador (`assets_hook.js`, `crypto/assets.mjs`):** desenha, calcula o texto, assina.
- **Nó/ledger (`BrdcLedger.Assets`):** executa e valida.

## Passo a passo
1. (dev) `mix brdc.asset class imovel --organ <chave hex> --veto 20` e `mix brdc.asset register imovel casa-1 <endereço do dono> "descrição" --organ-test 1`.
2. **Oferecer à venda** (tx 7): comprador + preço. Nada sai da conta. O dono pode **cancelar** (tx 9) até o aceite.
3. **Aceitar e pagar** (tx 8, comprador): o preço sai do saldo e fica em escrow; começa a janela de veto da classe.
4. Dentro da janela, o órgão pode **vetar** (tx 10): o dinheiro volta ao comprador. (Sem tela ainda.)
5. Passada a janela, **Finalizar venda** (tx 11, qualquer parte): o bem passa ao comprador, o preço vai ao vendedor. Bem com gravame não finaliza.

## O que é verificado e por quem
Dono, estado da negociação, gravame, saldo e prazo: ledger (`Assets.run/4`). Texto da revisão: calculado no navegador a partir dos mesmos campos da transação. Taxa: `asset_step_fee`, vinda do status do nó.

## O que pode dar errado
Saldo insuficiente (preço + taxa no aceite); oferta para si mesmo; bem com gravame; finalizar antes do fim da janela (a tela só oferece o botão depois); veto do órgão.

## Onde está no código
`apps/brdc_node/lib/brdc_node/{node,handler,client}.ex` (`assets_of`), `apps/brdc_web/assets/js/{assets_hook.js,crypto/assets.mjs}`, `apps/brdc_dev/lib/brdc_dev/authority.ex` e `lib/mix/tasks/brdc.asset.ex`.

## Testes que cobrem
`assets.test.mjs` (3, cargas iguais às do Elixir), `devnet_e2e_test.exs` (ciclo completo pela rede: classe, registro, oferta, aceite com escrow, finalização por relógio). **Verificado à mão no Chrome** com vendedor e comprador em origens diferentes: oferta de 30 BRDC, aceite, espera da janela (20 s) e finalização; saldos fecharam (comprador 100 → 69,96; vendedor 10 → 39,98) e o bem passou ao comprador.

## Limites honestos
- **Registro, veto e gravame** (que exigem assinatura coletiva do órgão) **ainda não têm tela**; só por `mix brdc.asset` (registro) ou transação direta.
- Sem notificação à outra parte: ela vê a oferta quando abre a carteira.
- O veto e a finalização antes do prazo não foram exercitados à mão (cobertos por testes do ledger).
