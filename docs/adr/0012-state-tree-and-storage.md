# ADR-0012 — Árvore de estado e armazenamento

**Status:** Proposto (aguarda confirmação do dono do produto)

## Contexto
O cabeçalho do bloco precisa de uma **raiz de estado** que resuma todas as contas e contratos, e os nós precisam guardar blocos e estado em disco.

## Proposta
- **Raiz de estado:** árvore de **Merkle esparsa** (chave = hash do caminho, valor = estado), permitindo provas de inclusão para o explorador e a carteira.
- **Armazenamento:** **CubDB** (Elixir puro, transacional, sem NIF) no começo, atrás de uma interface (`behaviour`) para trocar por RocksDB ou outro depois.
- Blocos e o **WAL do consenso** (rodada e bloqueio gravados antes de cada voto) em arquivos próprios.

## Alternativas
RocksDB (rápido, mas NIF); Mnesia (acopla à BEAM e complica a verificação); ETS + arquivo (simples, sem transações).

## Consequências
Provas de estado verificáveis por clientes; a troca de banco não afeta o consenso nem o ledger.
