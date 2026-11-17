# Como ler o código da Fase 3 (`brdc_consensus`)

Pré-requisito: [Consenso BFT](04-bft-consensus.md). Tudo em `apps/brdc_consensus/lib/brdc_consensus/`. Fluxo com diagrama: [Fluxo 03](../flows/03-consensus-round.md).

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `vote.ex` | voto assinado (prevote ou precommit; `nil` = voto nulo); a assinatura cobre rede, tipo, altura, rodada e bloco |
| 2 | `proposal.ex` | proposta assinada, com `valid_round` (prova de rodada anterior, `-1` se é bloco novo) |
| 3 | `certificate.ex` | certificado de commit: os precommits de mais de 2/3; `verify/3` confere sem confiar em ninguém |
| 4 | `engine.ex` | o motor de **uma altura**, sem I/O: `handle(motor, evento) → {motor, ações}` |
| 5 | `sim.ex` | simulador: tempo virtual, semente, atraso, partição, nó silencioso ou equivocador |

## Ideias-chave
- **Sem I/O:** o motor não conhece rede, relógio nem disco. Por isso o simulador consegue repetir exatamente uma falha: mesma semente, mesmo resultado.
- **Quórum:** `count * 3 > 2 * n`. Com 4 validadores são 3; com 7, são 5.
- **Trava (lock):** quem deu precommit num bloco só prevota em outro com prova de uma rodada mais nova. É isso que impede dois blocos finais.
- **Regras em laço:** depois de cada evento o motor aplica as regras até não haver mais nada (`settle/1`): decidir, pular rodada, prevotar, travar, anunciar prazos.
- **Ações:** `{:broadcast, msg}`, `{:schedule_timeout, passo, rodada}`, `{:need_block, rodada}`, `{:decide, bloco, certificado}`, `{:evidence, {a, b}}`.

## Rode você mesmo (`iex -S mix`)
```elixir
res = BrdcConsensus.Sim.run(n: 4, seed: 1)
map_size(res.decisions)                         # => 4 (todos decidiram)
{_bloco, cert} = res.decisions[0]
BrdcConsensus.Certificate.verify(cert, "sim", res.validators)   # => :ok
length(BrdcConsensus.Certificate.signers(cert)) >= 3             # => true

# proponente da rodada 0 fora do ar: a rodada seguinte decide
res = BrdcConsensus.Sim.run(n: 4, seed: 3, behaviors: %{1 => :silent})
elem(res.decisions[0], 1).round >= 1            # => true

# sem quórum: a rede pausa
BrdcConsensus.Sim.run(n: 4, behaviors: %{0 => :silent, 1 => :silent}, max_time: 60_000).decisions  # => %{}
```

## Limites honestos
Veja o [Fluxo 03](../flows/03-consensus-round.md): uma altura por vez, sem gossip, sem WAL, sem troca do conjunto ainda, sem auditoria.
