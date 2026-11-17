# ADR-0012 — Armazenamento em disco: log de blocos e estado por replay

**Status:** Aceito (dono do produto, 2026-11-17) · Substitui a proposta anterior (CubDB e árvore esparsa)

## Contexto
O nó guarda tudo em memória: um reinício apaga a rede. É preciso persistir blocos (com o certificado de commit) e, depois, a memória de voto do consenso. O critério do dono é **não depender de biblioteca mantida por uma pessoa só**.

## Decisão
1. **Fonte da verdade: o log de blocos**, em um arquivo, com `:file` do OTP (biblioteca padrão, sem dependência nova). Cada registro: tamanho (4 bytes), **soma de verificação** (SHA3-256 truncada em 16 bytes) e o bloco codificado (`Block.encode/1`; o certificado entra na M2). *Refinação feita ao implementar:* o `:disk_log` foi avaliado e **não** foi usado, porque não acrescenta nada ao formato próprio com soma e decodifica termos Erlang do arquivo; com `:file` cru lemos só bytes que nós mesmos enquadramos.
2. **O estado deriva dos blocos.** Ao subir, o nó **relê o log e reexecuta** cada bloco, conferindo a raiz de estado e o certificado de cada um. Estado e blocos nunca discordam por construção.
3. **Instantâneo** (estado + altura + último hash) para não reler tudo: **ainda não implementado**; só entra quando a releitura do log ficar lenta (medir antes). Quando entrar, é só aceleração e sempre pode ser descartado e refeito do log.
4. **Queda no meio da escrita:** a recuperação ignora a **cauda truncada** do log (registro incompleto ou com soma errada no fim) e continua do último bloco inteiro. Registro corrompido **no meio** é erro fatal (o operador resincroniza de outros nós).
5. **Escrita:** o nó só responde "incluída" depois do `sync` do bloco.
6. **Raiz de estado:** continua a árvore de Merkle simples de hoje. A **árvore esparsa com provas de inclusão** fica para quando o explorador ou um cliente leve precisarem (ADR próprio).
7. **Interface** `BrdcNode.BlockStore` (`behaviour`), para trocar a implementação sem tocar no consenso nem no ledger.
8. **Memória de voto do consenso (WAL):** rodada e bloqueio gravados antes de cada voto, em arquivo próprio (etapa M3).
9. **Propostas dos órgãos** (ADR-0024) ficam em `proposals.bin`, gravado por **troca atômica** (arquivo ao lado + renomear), **descartáveis** (não são consenso): ao ler, cada uma é conferida de novo contra o estado; arquivo ilegível = lista vazia.
10. **Hash da gênese** em `genesis.hash`: o nó recusa abrir o disco de outra rede (`:wrong_genesis`).

## Alternativas descartadas
CubDB (um mantenedor); RocksDB (NIF); Mnesia (acopla à BEAM); ETS + arquivo (sem recuperação definida).

## Consequências
Sem dependência nova; recuperação testável (cauda truncada, corrupção). Provas de estado ficam para depois, sem bloquear a Fase 7.
