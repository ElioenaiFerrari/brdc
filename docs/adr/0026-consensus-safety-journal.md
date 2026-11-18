# ADR-0026 — Diário de segurança do consenso: gravar antes de transmitir

**Status:** Aceito (dentro do plano da Fase 7 aprovado pelo dono em 2026-11-17, etapa M3) · Complementa o [ADR-0003](0003-bft-consensus-with-permissioned-validators.md) e o [ADR-0012](0012-state-tree-and-storage.md)

## Contexto
No BFT, um validador que assina **dois votos diferentes** na mesma rodada e tipo (ou duas propostas na mesma rodada) **equivoca**, e a rede o pune. Uma queda de energia ou reinício apaga a memória do motor: sem registro em disco, ao voltar ele pode assinar o contrário do que já saiu da máquina, ou **esquecer o bloqueio** num bloco e votar em outro, o que quebra a garantia de que dois blocos diferentes nunca ficam finais.

## Decisão
1. **Diário** (`BrdcNode.ConsensusWal`): cada proposta e cada voto **assinado por este validador** é gravado, com `sync`, **antes** de ser transmitido. Quem roda o motor só executa as transmissões se a gravação voltou `:ok`; se falhar, **nada** é transmitido.
2. **Retomada** (`Engine.restore/2`): do diário o motor reconstrói **rodada, passo e bloqueio** (o último precommit num bloco) e devolve as ações para continuar (prazos; pedido de bloco se for o proponente sem proposta feita).
3. **Garantia no motor:** `cast` e `propose` **nunca assinam duas vezes** o mesmo tipo de voto na mesma rodada, nem duas propostas na mesma rodada, com ou sem reinício.
4. **Diário ilegível = não vota.** Registro no meio do diário que não decodifica é erro fatal (`{:bad_wal, índice}`): é preferível ficar parado a arriscar a equivocação. **Cauda rasgada** é descartada, porque a mensagem correspondente **nunca saiu** (a transmissão só vem depois do `sync`).
5. O diário é **de uma altura**: ao decidir, é esvaziado (`advance/1`); ao abrir em altura nova, o que sobrou de altura antiga é descartado.
6. Votos e propostas ganham **codificação** (`Vote.encode/decode`, `Proposal.encode/decode`), a mesma que a M2 usa na rede.

## Limites honestos (também no modelo de ameaças, T22)
- **Apagar ou perder o diário** (restaurar o disco de um backup antigo, copiar a pasta para outra máquina) **reabre a janela de equivocação**. Regra de operação: **nunca** subir um validador com o diário vazio ou antigo, nem **dois processos com a mesma chave**. O nó não tem como detectar isso sozinho.
- Só as mensagens **próprias** vão ao diário. Se o validador estava **travado** num bloco que veio de outro, o bloco em si não está no diário: a **segurança** se mantém (o bloqueio é por hash), mas a **vivacidade** depende de os outros reenviarem a proposta (sincronização da M2).
- O motor **não retransmite**: depois da volta, quem completa as mensagens perdidas é a camada de gossip e sincronização da M2. Até lá, a segurança está provada em simulação; a vivacidade da volta, não.

## Alternativas descartadas
Gravar só o bloqueio (não cobre voto e proposta duplicados); gravar o estado inteiro do motor (mais frágil: o diário das mensagens assinadas é o mínimo suficiente e é verificável por assinatura); confiar em "reiniciar rápido" (não é segurança).

## Como foi testado
Unitários (com diário o motor não contradiz; **sem** diário ele equivoca, mostrado de propósito); bloqueio restaurado recusa o bloco novo; propriedades com quedas aleatórias no simulador (sem equivocação, no máximo um bloco final), com checagem de que as quedas **acontecem de fato**; diário em disco (ordem, cauda rasgada, registro ilegível, troca de altura, falha de gravação).
