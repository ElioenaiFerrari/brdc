# Fluxo 23 — Equivocação: um validador assina dois votos conflitantes

> Diagrama: **a gerar** (diagramas adiados a pedido do dono; foco na implementação).

## Resumo
**Equivocar** é o pior comportamento de um validador no BFT: assinar, na mesma altura e rodada, **dois votos para blocos diferentes**. Um honesto nunca faz isso (o diário de segurança do consenso, [ADR-0026](../adr/0026-consensus-safety-journal.md), o impede), então um validador que o faz está **comprometido ou malicioso**. Este fluxo mostra como a rede **detecta** isso e prova, com processos e containers de verdade, que **3 de 4 honestos continuam produzindo blocos**. É um **simulador de teste**: há **detecção, não punição** (não existe stake nem corte).

## Quem participa
- **Validador bizantino (simulado):** usa a semente de um validador de teste (o verdadeiro fica parado) e se conecta com a identidade dele.
- **Validadores honestos (3 de 4):** recebem os dois votos, detectam o conflito e contam uma evidência.
- **Você:** roda a simulação e lê o veredito.

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
**Rede local** (processos): `mix brdc.devnet.up` (4 ou mais validadores) e `mix brdc.devnet.equivocate [--victim K] [--duration 15s]`.
**Laboratório Docker:** `mix brdc.compose.up` e `mix brdc.compose.equivocate`.

O que acontece:
1. O validador `K` (padrão: o último) é **parado**; no Docker, o container `equivocator` assume o nome dele na rede e usa a semente dele.
2. O simulador entra na rede pelo P2P (TLS mútuo com a chave de consenso do `K`) e lê, pela consulta de consenso da porta pública, quantas evidências cada honesto tem **antes**.
3. Ele assina **dois prevotes** da altura seguinte (rodada 0), um para cada bloco inventado, e os envia a todos. Um voto da altura seguinte **abre o motor** do honesto, então não precisa de transação para provocar a detecção.
4. Cada honesto, ao receber o segundo voto do mesmo validador na mesma altura, tipo e rodada com outro bloco, emite **evidência** (`Engine.ingest_vote`), registra um aviso (`equivocação de <chave> na rodada 0`) e soma ao contador.
5. O simulador lê o contador de novo (`Client.consensus_info`): **passa** se **todos** os honestos subiram.
6. A ferramenta confere que a rede **continua viva**: uma emissão de teste enviada a um honesto ainda vira bloco em todos (3 de 4 mantêm o quórum de mais de 2/3), e religa o validador verdadeiro.

Saída esperada (Docker): `detectaram 3 de 3 validadores honestos` e `OK: equivocação DETECTADA por todos os honestos e a rede seguiu viva (só detecção: não há punição)`.

## O que é verificado e por quem
- **Cada honesto**, sozinho: confere a assinatura do voto, que o votante está na gênese, e que o novo voto conflita com o que já tem dele.
- **O simulador** só declara sucesso se **todos** os honestos mostrarem evidência maior que antes; **não confunde "não consegui ler" com "zero"**: se um honesto não responde à consulta de consenso, falha cedo com o motivo (aprendido da pior forma: o primeiro teste na rede local reportou "0 de 3" só porque o `mix brdc.node` ainda não servia a consulta).
- **Vivacidade:** depois da equivocação, a ferramenta submete uma transação e exige bloco novo nos honestos.

## O que pode dar errado
- **Não há punição:** o bizantino continua na rede, assina de novo e ninguém é cortado. Punir exige **stake** (fase futura, junto da revisão do [ADR-0027](../adr/0027-block-signers-and-fee-split.md)).
- **A evidência fica só na memória do nó** (`Replica`): some ao reiniciar, não vai para o disco e **não é espalhada** aos outros nem publicada na cadeia. Um validador que reinicia esquece o que viu.
- **Detecção depende do momento:** só detecta se os dois votos chegarem ao honesto com o motor da altura aberto; por isso o simulador reenvia (com blocos novos) até todos detectarem ou o tempo acabar.
- **Mais de 1/3 bizantino quebra o BFT:** com 4 validadores, 2 bizantinos podem parar a rede (e, com mais, até decidir blocos conflitantes). O simulador só faz um.
- **Um único validador malicioso ainda pode atrasar:** votos para a altura seguinte abrem o motor dos honestos sem transação; o efeito é só gastar rodadas, mas é uma superfície de abuso (a vivacidade foi reforçada em [ADR-0029](../adr/0029-propose-timeout-and-mempool-regossip.md)).
- **Só para validadores de teste:** o simulador exige a semente do validador; num ambiente real ninguém a tem.

## Onde está no código
`apps/brdc_dev/lib/brdc_dev/equivocation.ex` (o simulador), `compose/byzantine.ex` (o papel no container), `lib/mix/tasks/brdc.{devnet,compose}.equivocate.ex`; detecção em `apps/brdc_consensus/lib/brdc_consensus/engine.ex` (`ingest_vote`) e contagem em `apps/brdc_node/lib/brdc_node/replica.ex`; consulta `<<15>>` em `handler.ex` e `client.ex` (`consensus_info/1`).

## Testes que cobrem
`equivocation_test.exs` (3): 3 honestos por arquivos + o equivocador com a semente do 4º ⇒ **os 3 detectam** (evidência subiu) **e uma emissão ainda vira bloco com o mesmo hash**; chave fora da gênese não equivoca e sem pares dá erro claro; **falha cedo quando não dá para ler a evidência**. Rodado **60 vezes seguidas sem falha** (depois das correções do ADR-0029; antes, 1 em 20 travava). **Verificado à mão:** rede local com 4 processos reais (`3 de 3 detectaram`, rede viva) e no Docker, **duas vezes** (`3 de 3`, `v4` verdadeiro religado e sincronizado).

## Limites honestos
- É **uma** forma de equivocação (dois prevotes na rodada 0); não cobre dois precommits, dois blocos propostos nem equivocação em rodadas altas.
- O ataque é **local e cooperativo**: o simulador conhece a semente. Não prova nada sobre um atacante que só controla a rede.
- **Sem punição, a detecção não muda o futuro:** a rede só mostra a evidência.
