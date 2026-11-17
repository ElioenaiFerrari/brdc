# ADR-0003 — Consenso BFT com validadores autorizados

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
A rede precisa concordar sobre a ordem das transações. Opções: **BFT com validadores autorizados** (Tendermint/HotStuff: bloco final em uma rodada); **prova de participação aberta** (Ethereum: qualquer um faz stake, forks temporários, finalidade lenta); **Proof of Authority simples** (um líder por vez, sem quórum).

## Decisão
**BFT com validadores autorizados e finalidade imediata.** Um conjunto de validadores (poder **igual** no início) decide blocos em **rodadas**: o proponente propõe, os validadores dão prevote e precommit; com **mais de 2/3** dos precommits o bloco é **final** (certificado de commit). Se o proponente falha, a rodada seguinte tem outro. **Sem blocos vazios:** a cadeia só cresce quando há transação. O conjunto muda por rotação aprovada por mais de 2/3. Abrir para **stake** é fase futura.

## Alternativas descartadas
Prova de participação aberta (complexidade de incentivos, seleção de validadores e penalidades); PoA simples (sem finalidade BFT: um líder malicioso forja forks).

## Consequências
- Sem quórum a rede **pausa** em vez de bifurcar; mais de 1/3 em conluio pode parar a rede; mais de 2/3 pode decidir qualquer coisa.
- O motor é uma máquina de estados **sem I/O** (`brdc_consensus`), testada por simulação (partição, atraso, proponente bizantino, equivocação).
- Pendente: tempo de bloco, validadores iniciais e governança do conjunto.

## Referência
Mesmo desenho do ADR-0034/0045 do projeto Teko, reescrito para OTP.
