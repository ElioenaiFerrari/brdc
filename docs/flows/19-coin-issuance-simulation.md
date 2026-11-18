# Fluxo 19 — Produção da moeda (simulada): lastro, emissão, resgate

> Diagrama: **a gerar** (adiado pelo dono; foco na implementação).

## Resumo
O BRDC vale R$ 1 e nasce **lastreado**: o banco recebe reais, os emissores **atestam a reserva** e então **emitem** BRDC (mint); quem quer sair **resgata** (burn) e o banco devolve os reais, e os emissores **reduzem o lastro**. Tudo exige **M de N emissores** (na rede de teste, 2 de 2). As ferramentas `mix brdc.*` simulam esse ciclo com as chaves de teste, para ver a moeda funcionar sem abrir o navegador. A rede **só informa a cobertura** (reserva atestada contra o que circula): não prova os reais e não congela nada ([ADR-0009](../adr/0009-no-freezing-uncensored-brdc.md)).

## Quem participa
- **Emissores** (papéis `i1` e `i2` de teste, 2 de 2): atestam reserva, aprovam mint e burn.
- **Titular** (carteira de teste, por exemplo `sim-alice` e `sim-bob`): recebe, paga e pede o resgate.
- **Banco** (fora da rede): recebe e devolve os reais; na simulação é só texto.
- **Validadores:** executam e registram tudo em bloco, com taxa para eles.

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
Pelo cenário pronto: `mix brdc.devnet.up` e `mix brdc.simulate issuance`. Ou passo a passo:
1. **Lastro.** `mix brdc.reserve 1000`: os emissores atestam **R$ 1.000 em caixa** (o total, com número de sequência 1, 2, 3…).
2. **Emissão.** `mix brdc.mint alice 1000`: os emissores aprovam o mint de 1.000 BRDC para a Alice. Cada referência de depósito só vale uma vez.
3. **Uso.** `mix brdc.send alice bob 250`: transferência com taxa mínima; a taxa vai aos validadores, a **oferta não muda**.
4. **Resgate.** `mix brdc.burn bob 250`: a Bob pede, os emissores aprovam e o ledger **queima** (só o dono da conta queima, e não mais do que tem). A oferta cai 250.
5. **Baixa do lastro.** O banco paga R$ 250 à Bob; `mix brdc.reserve 750` atesta a reserva nova.
6. **Conferir.** `mix brdc.supply` mostra emitido, queimado, em circulação (**emitido − queimado**), a reserva atestada e a **cobertura**: *exata* (reserva = oferta), *coberta* (sobra) ou *ABAIXO* (faltam reais).

## O que é verificado e por quem
- **Ledger:** mint e burn exigem M-de-N emissores (assinaturas sobre um documento amarrado à rede, conta, valor e referência); referência repetida é recusada; burn só do dono e com saldo; atestado com sequência certa.
- **Cenário (`mix brdc.simulate issuance`):** além de executar, **confere no fim**: oferta cresceu 750, emitido +1.000, queimado +250, reserva +750, cobertura não piorou, a Bob terminou como começou e a Alice com 750 menos a taxa; **prova que um mint com um só emissor é recusado**. Sai com erro se algo não bater.

## O que pode dar errado
- **Reserva abaixo da oferta** (emissor atesta menos do que circula): a rede **mostra** "ABAIXO", mas não impede nada. A confiança nos emissores é o risco da stablecoin (ADR-0002/0009).
- **Atestado falso:** a rede só prova que M emissores **assinaram**, não que os reais existem.
- **Resgate sem baixa do lastro:** esquecer de reduzir a reserva deixa a cobertura "sobrando" sem motivo; a ferramenta não decide por você.

## Onde está no código
`apps/brdc_ledger/lib/brdc_ledger/executor.ex` (mint, burn, atestado) e `state.ex` (`coverage/1`); `apps/brdc_node/lib/brdc_node/{node,handler,client}.ex` (consulta de oferta e reserva, porta pública `<<8>>`); `apps/brdc_dev/lib/brdc_dev/{issuance,simulation,wallets,chain,cli}.ex`; tarefas `apps/brdc_dev/lib/mix/tasks/brdc.{reserve,mint,burn,supply,send,simulate,wallet.new,wallet.list,fund,balance}.ex`.

## Testes que cobrem
`simulation_test.exs` (6: cenário completo, duas rodadas, M-de-N, resgate, atestados e cobertura), `wallets_test.exs` (5). **Verificado à mão** com 4 validadores em processos reais (`mix brdc.devnet.up`): o cenário passou duas vezes seguidas e os comandos avulsos (`wallet.new`, `mint`, `send`, `burn`, `reserve`, `supply`) funcionaram, inclusive a cobertura "ABAIXO" quando a reserva é menor que a oferta.

## Limites honestos
- **Só rede de teste:** as chaves dos emissores e a frase das carteiras de teste ficam em texto puro em `net/` (nunca em release).
- **Emissores de teste são 2 de 2**; a governança real dos emissores (ADR-0013) não está ligada às ferramentas.
- **Não há banco nem Pix**: os "reais" da simulação são só o número do atestado.
- **Sem tela na carteira web** para emitir ou resgatar; o ciclo é por linha de comando.
