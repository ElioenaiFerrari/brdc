# Fluxo 24 — Teste de carga do laboratório Docker

> Diagrama: **a gerar** (diagramas adiados a pedido do dono; foco na implementação).

## Resumo
`mix brdc.compose.load` mede o que a rede aguenta com os validadores em containers de recursos limitados. A carga é **aberta, em degraus**: cada degrau oferece uma taxa fixa de transferências por segundo (repartida entre 8 remetentes, cada um preso a um validador para a ordem dos nonces valer) e mede o resultado. Um laço fechado (mandar o mais rápido possível) sempre empurra o sistema para a saturação e não diz **onde** ela começa.

## Quem participa
- **A ferramenta** (no seu computador): assina e envia as transações, lê o estado dos validadores pela porta pública e o cgroup de cada container.
- **Os 4 validadores** do laboratório ([fluxo 22](22-docker-lab.md)), cada um com 0,5 CPU e 384 MiB.

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono; foco na implementação).

## Passo a passo
`mix brdc.compose.up`, depois `mix brdc.compose.load [--rates 50,100,200,400] [--step 20s] [--repeat 3] [--senders 8] [--drain 60s] [--warmup 20s] [--no-stop]`.
1. Cria e financia as contas de remetente (fora da medição).
2. **Aquecimento na taxa do primeiro degrau** (descartado): o primeiro degrau pesado paga alocação de memória e caches e, com um aquecimento leve, saía 2 a 3 vezes pior que os seguintes.
3. Para cada degrau (e cada repetição): oferece a taxa pelo tempo do degrau, espera esvaziar o que ficou pendente e mede.
4. Para no primeiro degrau **saturado** (`--no-stop` continua).
5. Resumo por repetição e, com `--repeat`, **mediana e faixa** por taxa.

## O que é medido
- **Oferecidas × aceitas** e os motivos de recusa; latência de ida e volta do envio.
- **Latência de confirmação**: do envio até o nonce confirmado do remetente passar dele, lido a cada 100 ms (precisão ~100 ms).
- **Esvaziamento** e transações que **não** confirmaram; **blocos** (quantidade, tx por bloco, intervalo).
- **CPU, throttling e memória lidos do cgroup** de cada validador (CPU em núcleos, tempo e fração de períodos limitados, memória atual e pico, `oom_kill`).
- **Fofoca entre nós**: aceitas, duplicadas e recusadas por motivo.
- **Saúde:** reinícios e `docker events` (`die` com o código de saída **real** e `oom`): ler `docker inspect` depois de um reinício **engana** (ExitCode e OOMKilled passam a ser do processo novo).
- Saturado = não esvaziou, esvaziou em mais de 15 s, aceitou menos de 95% do oferecido, ou algum container reiniciou.

## O que foi achado com ela (e corrigido)
- **`Node.submit` ficava 32 vezes mais lento com o mempool cheio** (0,48 ms vazio, 15,5 ms com 7.500 pendentes): refazia o hash de todas as pendentes a cada envio. Agora é O(1) com um conjunto de ids (0,09 a 0,12 ms), e há teste de regressão verificado por mutação.
- **Os validadores morriam por falta de memória** com 192 MiB (evento `oom`, saída 137), todos juntos, porque todos guardam o mesmo mempool. O padrão passou a 384 MiB. Pico medido por validador: ~135 MiB a 50 tx/s, ~190 a 200, ~215 a 400, ~290 a 800.
- Com memória folgada (512 MiB), a rede **sustentou 400 tx/s** (p50 1,9 s, p95 3,0 s de confirmação, sem backlog) e **saturou em 800 tx/s** (aceitou 702/s e levou 23 s para esvaziar).
- **A fofoca é 75% duplicata:** cada transação chega 12 vezes em vez de 3 (cada nó repassa a todos os pares, inclusive a quem mandou). Está como melhoria futura.
- Minha hipótese de que a latência de 100 tx/s vinha de nonces fora de ordem na fofoca **não se confirmou** (12 recusas em 6.000): o que apareceu foi aquecimento (p50 de 3,6, 2,4 e 1,9 s em repetições do mesmo degrau).

## O que pode dar errado
- **A última rodada precisa (384 MiB, 3 repetições) não chegou a ser executada**; os números acima vêm de rodadas anteriores, todas medidas, mas com configurações diferentes (192 e 512 MiB).
- **Um só computador e Docker em VM:** o throttle e a memória são do cgroup do container, mas a CPU do host é compartilhada com a ferramenta.
- **Latência de confirmação com ~100 ms de resolução** e blocos com horário em segundos.
- A ferramenta **para no primeiro degrau saturado** por padrão, para não castigar a máquina.

## Onde está no código
`apps/brdc_dev/lib/brdc_dev/load.ex` (partes puras e o degrau) e `apps/brdc_dev/lib/mix/tasks/brdc.compose.load.ex`; contadores de fofoca em `apps/brdc_node/lib/brdc_node/{replica,handler,client}.ex` (consulta `<<15>>`).

## Testes que cobrem
`load_test.exs` (11: percentil, resumo, leitura e diferença do cgroup, calendário de envio e contagem oferecida), `mempool_ids_test.exs` (3: duplicata, id sai do conjunto depois do bloco, custo de enviar não cresce com o mempool), `validator_test.exs` (contadores de fofoca).

## Limites honestos
- Mede **uma configuração** (4 validadores, 0,5 CPU, loopback do Docker); não prevê o comportamento em rede real.
- Carga só de **transferências simples** (a mais barata); contratos e bens custam mais.
