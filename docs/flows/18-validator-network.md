# Fluxo 18 — Rede de vários validadores: do envio da transação ao bloco com certificado

> Diagrama: **a gerar** (adiado pelo dono; foco na implementação).

## Resumo
Cada validador roda um **nó** (estado, mempool, disco), uma **réplica** (motor BFT, diário de segurança) e uma **rede de pares** (TLS 1.3 mútuo). Uma transação enviada a **qualquer** nó é espalhada a todos; o proponente da rodada monta o bloco; mais de 2/3 dos validadores votam; o bloco é confirmado **com o certificado de commit** em todos. **Sem transação pendente, não há bloco** (e a rede fica em silêncio).

## Quem participa
- **Carteira:** fala com **um** nó pela porta pública (qualquer um serve); não confia nele.
- **Validadores** (conjunto do gênese, poder igual): cada um com `BrdcNode.Node`, `BrdcNode.Replica` e `BrdcNode.Peers`.
- **Proponente da rodada:** rodízio determinístico entre os validadores (`altura + rodada`).

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
1. **Entrada.** A transação chega a um nó (`Node.submit`): é validada contra o estado com as pendentes e entra no mempool. O nó avisa a réplica, que a **espalha** a todos os pares (`{:tx}`); cada par a valida e, se for nova, repassa (duplicada é descartada).
2. **Início da altura.** Com transação pendente, a réplica espera `interval_ms` (agrupamento; 1 s na devnet) e inicia a altura. Quem ainda está parado **inicia** ao receber a primeira mensagem de consenso daquela altura.
3. **Proposta.** O proponente monta o bloco do seu mempool (`Node.build_proposal`): cabeçalho com `signers` = conjunto de validadores ([ADR-0027](../adr/0027-block-signers-and-fee-split.md), aceito), horário do relógio, raiz de estado. Sem transação para propor, espera uma chegar ou o prazo da rodada passar.
4. **Voto.** Cada validador **confere o bloco por inteiro** (`Node.check_block`: assinantes, horário plausível, execução completa, raiz de estado) e dá **prevote**; com mais de 2/3 de prevotes no bloco, **trava** e dá **precommit**. Antes de transmitir qualquer proposta ou voto próprio, a réplica **grava no diário** (ADR-0026).
5. **Decisão.** Mais de 2/3 de precommits = bloco final com **certificado de commit**. O nó confere o certificado de novo, executa, **grava em disco** (bloco + certificado) e limpa o mempool. A réplica esvazia o diário, avisa os pares (`{:blocks}`) e, se sobrou transação, começa a próxima altura.
6. **Sem quórum.** Se menos de 2/3 estão no ar, a rede **para** (não bifurca); ao voltar quórum, retoma.
7. **Quem entra atrasado ou volta.** Ao (re)conectar, os pares trocam `{:status, altura}` e **reenviam o que sabem da altura em curso** (mensagens assinadas, verificáveis por qualquer um). Quem está atrás pede blocos (`{:get_blocks}`) e **confere o certificado de cada um** antes de aceitar.

## O que é verificado e por quem
- **Handshake:** chave do par no conjunto de validadores, `chain_id` e hash da gênese iguais (`Channel`).
- **Guarda** (`Guard`): tetos por IP e por chave, pontos, banimento; taxa por sessão larga para o consenso (500 msg/s).
- **Cada mensagem** (`Wire.decode`): formato estrito; malformada derruba a sessão.
- **Voto e proposta:** assinatura, proponente da rodada, hash do bloco (motor). Proposta com `block.proposer` diferente do proponente é descartada (a réplica).
- **Bloco:** execução completa por **cada** validador antes do prevote; certificado conferido por quem confirma e por quem sincroniza.

## O que pode dar errado
- **Proponente fora do ar:** o prazo da rodada passa, prevotes nulos, rodada seguinte com outro proponente.
- **Dois ou mais validadores fora:** sem quórum a rede espera; nada é decidido (e nada se perde).
- **Equivocação** (dois votos diferentes na mesma rodada): o motor registra a **evidência** (ainda sem punição).
- **Par lento:** fila de envio acima do teto desconecta o par; ele reconecta.
- **Par mentiroso na sincronização:** bloco sem certificado válido ou que não executa é recusado e o par é desconectado.
- **Falha ao gravar o diário:** a réplica **para** (falha fechada); nada é transmitido.

## Onde está no código
`apps/brdc_node/lib/brdc_node/{replica,peers,wire,node,consensus_wal}.ex`; `apps/brdc_consensus/lib/brdc_consensus/{engine,certificate,vote,proposal}.ex`; `apps/brdc_p2p/lib/brdc_p2p/` (canal, listener, guarda).

## Testes que cobrem
`cluster_test.exs` (**4 validadores em TLS real**: uma transação a um nó vira bloco em todos com certificado; transações em nós diferentes ao mesmo tempo; proponente fora do ar e volta; sem quórum a rede para e retoma; entrada tardia com sincronização; rajada de 24 transações; reinício no meio; **a carteira pela porta pública de qualquer nó**), `multi_commit_test.exs` (9: cabeçalho, certificado ruim, idempotência, disco), `peers_test.exs` (6), `wire_test.exs` (4), `restore_test.exs` (reenvio e quedas simuladas).

## Limites honestos
- **Conjunto de validadores fixo** (o do gênese); a troca por governança (ADR-0013) ainda não está ligada à rede.
- **Endereços dos pares estáticos** (lista na configuração); a descoberta por registros assinados existe no P2P, mas não está ligada aqui. Entra no roteiro de dois computadores.
- **Todos na mesma máquina** nos testes automáticos; a rede entre computadores é validada à mão (M6).
- **Equivocação só gera evidência**, sem punição.
- **O prazo da proposta vale também para o proponente e o mempool é reenviado a quem conecta** ([ADR-0029](../adr/0029-propose-timeout-and-mempool-regossip.md)): achado pelo simulador de equivocação.
- **Taxa repartida entre todos os validadores** do conjunto, não só entre quem assinou: ADR-0027 (**Aceito**; repartir só entre quem assinou fica para quando houver stake).
- Sem criptografia em repouso e sem controle de quem lê o disco do nó.
