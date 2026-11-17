# 4. Consenso BFT

## O problema
Vários computadores, de instituições diferentes, que **não confiam uns nos outros**, precisam concordar sobre **qual bloco é o próximo**. Alguns podem estar fora do ar, lentos ou mentir (falha **bizantina**).

## A ideia (Tendermint/HotStuff)
Há um conjunto de **validadores**. O tempo se divide em **alturas** (uma por bloco) e cada altura em **rodadas**:

1. **Proposta:** o proponente da rodada (sorteado de forma determinística) propõe um bloco.
2. **Prevote:** cada validador vota no bloco se ele é válido.
3. **Precommit:** quem viu mais de 2/3 de prevotes no mesmo bloco dá precommit (e se "trava" nesse voto).
4. Com **mais de 2/3 de precommits**, o bloco é **final**; os precommits juntos formam o **certificado de commit**.

Se o proponente falhou ou a rede atrasou, passa o tempo-limite e a **rodada seguinte** tem outro proponente.

## Por que mais de 2/3?
Com N validadores e até F maliciosos, N ≥ 3F + 1 garante: dois grupos de "mais de 2/3" sempre se sobrepõem em pelo menos um validador **honesto**. Logo, **dois blocos diferentes nunca ficam finais na mesma altura** (segurança). E o sistema segue andando se pelo menos mais de 2/3 estão vivos (vivacidade).

| Validadores | Quórum (> 2/3) | Falhas toleradas |
|---|---|---|
| 3 | 3 | 0 |
| 4 | 3 | 1 |
| 7 | 5 | 2 |

## Finalidade imediata e "sem blocos vazios"
Diferente do Bitcoin, **não há "esperar 6 confirmações"**: bloco decidido é definitivo. Se não há quórum, a rede **pausa** em vez de bifurcar. E a BRDC **não produz blocos vazios**: uma altura só começa quando há transação esperando (depois de um curto intervalo de agrupamento).

## O que um validador malicioso pode fazer
- **Equivocar** (votar em dois blocos na mesma rodada): é detectável; os dois votos assinados são **evidência**.
- **Censurar** (não incluir transações): a rodada seguinte tem outro proponente.
- Com mais de 1/3 em conluio, pode **parar** a rede; com mais de 2/3, **decidir qualquer coisa**.

## Como a BRDC usa
O motor é uma **máquina de estados sem I/O** (`brdc_consensus`): recebe eventos (mensagem, tempo esgotado) e devolve **ações** (enviar voto, gravar). Isso permite testar tudo por **simulação determinística** (partições, atrasos, proponente bizantino). O conjunto muda por rotação aprovada por mais de 2/3. Decisão: [ADR-0003](../adr/0003-bft-consensus-with-permissioned-validators.md).

## Onde está no código
Fase 3 pronta: veja [Como ler o código da Fase 3](12-reading-phase-3-code.md).

## Para ir além
Projeto irmão Teko: `teko-bft` (Rust) implementa este mesmo desenho.
