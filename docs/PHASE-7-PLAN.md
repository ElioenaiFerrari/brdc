# Plano da Fase 7 — rede de vários validadores, persistência, explorador e testnet

> **Estado: aprovado pelo dono do produto em 2026-11-17** (D1 a D5 aceitas conforme a recomendação; ver [ADR-0012](adr/0012-state-tree-and-storage.md) e [ADR-0025](adr/0025-block-interval-and-otp-libraries.md)). Implementação em andamento, etapa por etapa.

## Objetivo
Sair de "um nó de um validador em memória" para uma **rede de teste de verdade**: vários validadores em BFT conversando por P2P, com **disco**, **explorador**, ferramentas de desenvolvimento e um **roteiro validado em dois computadores**. Ao fim, a revisão geral que você pediu para o final da última fase.

## Onde estamos
O ledger, o consenso (motor sem I/O, testado por simulação) e o P2P (TLS 1.3 mútuo, limites, descoberta, porta pública) existem e estão testados **separados**. O `brdc_node` hoje é um validador único, sem rede entre validadores e sem disco. A carteira já fala com um nó pela porta pública.

## Decisões pendentes (com recomendação)

| # | Decisão | Recomendação | Por quê |
|---|---|---|---|
| D1 | **Armazenamento (ADR-0012)** | **Log de blocos em disco, só com a biblioteca padrão do OTP** (`:file` com `sync`; o `:disk_log` foi avaliado e dispensado, ver ADR-0012), estado reconstruído por replay, com **instantâneo** periódico. **Não** usar CubDB agora. A raiz de estado continua a árvore de Merkle simples de hoje; a **árvore esparsa com provas** fica para quando o explorador ou um cliente leve precisarem. | Seu critério de não depender de lib mantida por uma pessoa só (o CubDB tem um mantenedor). O `:disk_log` é da biblioteca padrão do OTP. O estado é pequeno e deriva dos blocos, então o log é a fonte da verdade. |
| D2 | **Intervalo entre blocos (P3)** | Bloco **só quando há transação pendente**, depois de **1 s** de agrupamento na devnet e **2 s** na testnet, com teto de **500 transações ou 256 KiB** por bloco (ajustáveis, a medir). **Sem bloco vazio e sem batimento.** | Já combinado antes ("tempo, não número de blocos"). Como as janelas e prazos agora são avaliados no horário do **próximo** bloco, um batimento seria desperdício. |
| D3 | **Aceitar ADR-0023 e ADR-0024** | Aceitar os dois. | Já estão implementados e verificados à mão. |
| D4 | **Bibliotecas OTP (P7)** | **Nenhuma nova** nesta fase: `GenServer`, `Registry`, `Task.Supervisor`, `:file`, `:telemetry` (já vem com o Phoenix, mantido por uma organização). Sem GenStage, Broadway, Flow ou Benchee até haver **medição** que justifique. | Menos superfície de supply chain; medir antes de otimizar. |
| D5 | **Persistir as propostas dos órgãos** | **Sim, no mesmo log**, como registros de um tipo próprio, descartáveis (não são consenso). | Hoje somem no reinício; é só conveniência, mas incomoda no uso real. |

## Etapas (cada uma só começa com a anterior verde e documentada)

### M1 · Persistência (D1, D5)
`BrdcNode.BlockStore` (behaviour) + implementação em `:file`: registro com tamanho, soma de verificação e bloco com seu certificado; escrita com `sync` antes de responder; recuperação **tolerante a cauda truncada** (queda no meio da escrita). Subida do nó = replay de blocos + conferência da raiz de estado e dos certificados. Instantâneo periódico para não reler tudo. `mix brdc.devnet.reset` apaga.
**Testes:** reinício preserva saldos, contratos, bens e credenciais; cauda truncada e registro corrompido; bloco com certificado inválido no disco é recusado; propriedade "replay = estado ao vivo".

### M2 · Nó com vários validadores
`BrdcNode.Replica`: liga o `Engine` (um por altura) à rede: **pares** a partir dos registros de endereço e da descoberta; **gossip de transações** (mempool replicada, com limite e deduplicação); **propostas, votos e certificado** pelos canais TLS; **temporizadores** de rodada; **sincronização de blocos** para quem entra atrasado (confere certificado de cada bloco). Cada nó mantém a **porta pública**, então a carteira conecta em qualquer um. Registro de **evidência de equivocação** (sem punição ainda).
**Testes (4 validadores na mesma VM, em TCP/TLS real):** bloco decidido por todos; **cai 1 → continua** (3 de 4); **caem 2 → para e retoma** quando volta; proponente falho gira; nó atrasado sincroniza; transação enviada a qualquer nó chega a todos; saldos finais iguais; sem fork.

### M3 · Memória de voto do consenso (WAL)
Rodada e bloqueio **gravados antes de cada voto**, para um validador que reinicia **nunca votar duas vezes** na mesma altura e rodada. **Teste:** matar e subir o nó no meio de uma rodada sem equivocar.

### M4 · Explorador
Página `/explorer` (LiveView, só leitura) falando com o nó pela porta pública: blocos, transações, contas, contratos, bens, credenciais, validadores, **quem assinou cada bloco** (pelo certificado) e busca. Consultas novas na porta pública (intervalo de blocos, transação por id) com limites. **Teste:** o que o explorador mostra bate com o estado do nó; consulta fora de limite é recusada.

### M5 · Ferramentas
Catálogo de `mix brdc.*` do `brdc_dev` (init/up/down/status/reset/logs, wallet.new, send, blocks, explorer), **simuladores** (blocos sob demanda, equivocação, rotação de validadores) e `mix brdc.docs.check` com exemplos executáveis. Só dev, nunca em release.

### M6 · Roteiro de dois computadores
Geração de chaves e gênese (`brdc.keygen` e `brdc.genesis` já existem), troca dos arquivos públicos, subida em duas máquinas, envio e consulta cruzados. Fica **escrito, ensaiado e anotado** em `docs/NETWORKS.md`; validado à mão (a rede entre máquinas não tem teste automático equivalente, dito honestamente no doc).

### M7 · Revisão geral final (você pediu)
Releitura de **todo** o código e dos docs; passada no **modelo de ameaças** (T1 em diante); **auditoria de dependências**; guia de leitura do código; **diagramas**: migrar os 12 existentes para o tema escuro do BRDC e gerar os dos fluxos 13 a 17 (adiados por você até aqui). Relatório final com o que ficou de fora.

## Ordem e dependências
M1 → M3 (o WAL usa o mesmo mecanismo de disco) → M2 (precisa de M1 para o nó reiniciar e sincronizar) → M4 → M5 → M6 → M7. M5 pode andar em paralelo a partir do M2.
Tamanho relativo: M2 é o maior (cerca de metade da fase); M1, M3, M4 médios; M5 e M6 pequenos; M7 médio.

## Riscos e como lidamos
- **Consenso sob rede real** (atrasos, partição, equivocação) é onde as surpresas moram: os testes de M2 injetam falhas (matar nó, cortar conexão, atrasar) e a regra é **sem fork, sem voto duplo**.
- **Relógio:** o bloco usa o relógio do proponente e nunca recua; validadores rejeitam bloco com horário muito à frente (limite a definir no M2, **decisão de parâmetro** a registrar no ADR).
- **Disco:** queda no meio da escrita é o caso a testar de propósito (M1).
- **Escopo:** a Fase 7 **não** inclui stake nem validadores abertos (futuro); a lista de validadores continua a do gênese e das trocas por governança (ADR-0013).

## O que eu preciso de você
Responder **D1 a D5** (basta "ok" para aceitar as recomendações, ou dizer o que muda). Em seguida eu registro os ADRs (0012 aceito com o desenho acima, ADR novo para o P3 e para o relógio, 0023 e 0024 aceitos) e começo pelo **M1**.
