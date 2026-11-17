# 9. OTP e desempenho

## A ideia central
A BEAM (a máquina virtual do Erlang/Elixir) foi feita para **muitos processos pequenos e isolados** que trocam mensagens e se recuperam de falhas por **supervisão**. Isso casa bem com um nó de blockchain: receber transações, verificar assinaturas, falar com vários pares e guardar blocos são tarefas diferentes e quase independentes.

Mas há uma regra de ouro para a BRDC: **o que decide o estado precisa ser determinístico e simples**. Desempenho se ganha **nas bordas** (rede, verificação, leitura), nunca complicando o caminho que todos os nós precisam executar de forma idêntica.

## Onde cada peça cabe

| Peça | O que faz | Onde cabe na BRDC | Onde NÃO usar |
|---|---|---|---|
| **GenServer** | um processo com estado e fila de mensagens | o motor de consenso (um por rede), o mempool, cada sessão P2P | como gargalo de leitura de estado |
| **Supervisor / DynamicSupervisor** | reinicia processos que caem | toda a árvore do nó; uma sessão por par | |
| **Registry** | acha processos por nome/chave | sessões por chave de validador | |
| **ETS** | tabela em memória, leitura concorrente sem fila | cache de estado para leituras (saldo, conta), mempool indexado | fonte da verdade do consenso (a verdade é o ledger + disco) |
| **Task.async_stream** | executa em paralelo com limite | **verificar assinaturas** de um bloco em todos os núcleos | |
| **GenStage** | pipeline produtor/consumidor com **contrapressão** | mempool → montagem de bloco; fila de blocos a aplicar | lógica de consenso |
| **Broadway** | ingestão com lotes, retentativas e métricas, em cima do GenStage | entrada de transações vindas do RPC/rede (validar em lote, repassar) | execução do ledger |
| **Flow** | processamento paralelo de coleções, em cima do GenStage | recalcular índices do explorador, varreduras grandes | caminho determinístico |
| **Reactor** | orquestração de passos com dependências, compensação (saga) | **fluxos longos de fora do consenso**: onboarding, publicação e acompanhamento de um contrato, rotinas das mix tasks | dentro do consenso ou do ledger |
| **:telemetry** | métricas e eventos | medir tudo (latência de bloco, fila, verificações) | |
| **Benchee** | benchmark | decidir **com número** antes de otimizar | |

## Por que o ledger e o consenso ficam "simples"
- **Ledger:** é uma função pura `aplicar(estado, bloco)`. Se um framework de orquestração decidisse a ordem ou paralelizasse a execução de forma não determinística, dois nós poderiam divergir. Paralelizar a **verificação de assinaturas** é seguro (é um "sim/não" independente); paralelizar a **execução** só com cuidado (transações que tocam as mesmas contas precisam de ordem).
- **Consenso:** é uma máquina de estados sem I/O, num único processo, que recebe eventos e devolve ações. Simplicidade e testabilidade vêm antes de velocidade: o gargalo de uma rede BFT é o número de rodadas de mensagens, não a CPU do nó.

## Um desenho provável (a confirmar nas fases)
```
RPC/rede ──> Broadway (valida em lote, Task.async_stream nas assinaturas)
         ──> Mempool (GenServer + ETS)
         ──> GenStage (produtor: mempool; consumidor: montagem de bloco, com contrapressão)
         ──> Consenso (GenServer, máquina de estados)
         ──> Ledger.apply (puro) ──> disco ──> ETS (cache de leitura) ──> LiveView (PubSub)
```

## Regras para adotar uma biblioteca
1. **Medir primeiro** (Benchee, telemetry): sem número, sem otimização.
2. **Justificar** (supply chain): mantenedores, atividade, tamanho, alternativa na OTP.
3. **Nunca** no caminho determinístico do ledger nem dentro do motor de consenso.
4. Registrar a escolha no ADR da fase (decisão P7 em [adr/README.md](../adr/README.md)).

## Onde está no código
*Planejado (a partir das Fases 2, 3 e 7).*
