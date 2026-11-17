# Nó da BRDC (Fase 7; ferramentas da Fase 4)

Aplicação OTP que vai juntar ledger, consenso e rede.

**Estado:** nó local de **um validador** pronto (`BrdcNode.Node`, estado, mempool e blocos sem blocos vazios; ponte para a porta pública e cliente: [Fluxo 14](../../docs/flows/14-local-node-and-send.md)). Ainda não liga o motor BFT nem o P2P entre validadores. Já tem as ferramentas de rede da Fase 4: `Keygen` (chave do validador, semente 0600) e `Genesis` (documento da rede e sua impressão digital), com as tarefas `mix brdc.keygen` e `mix brdc.genesis`. Fluxo: [07](../../docs/flows/07-keygen-and-genesis.md). Veja o [roteiro](../../docs/PHASES.md) e o [guia de conceitos](../../docs/concepts/README.md).
