# ADR-0029 — O prazo da proposta vale para o proponente, e o mempool é reenviado a quem conecta

**Status:** **Aceito** (2026-11-18; correção de vivacidade achada pelo simulador de equivocação, alinhada ao que o código já dizia pretender) · Toca o [ADR-0003](0003-bft-consensus-with-permissioned-validators.md)

## Contexto
O simulador de equivocação ([fluxo 23](../flows/23-equivocation.md)) revelou, em **cerca de 1 de cada 20 execuções**, a rede **parada** depois do voto duplo (altura 1, rodada 0, nenhum timeout avançando). A investigação achou **dois defeitos independentes**:

1. **Proponente sem prazo.** `Engine.start_round/2` só agendava o timeout de `propose` para quem **não** era proponente. O proponente sem nada para propor (mempool vazio: a rede não faz bloco vazio) pedia o bloco, a réplica ficava em `waiting_block` "até chegar uma transação ou o prazo da rodada passar" (o comentário do código) e **o prazo nunca existia**. Se a transação não chegasse a esse proponente, ele **nunca votava**; com um bizantino calado, os dois honestos restantes (2 de 4) não fazem 2/3 de nada e a rodada não anda.
2. **Fofoca perdida.** A fofoca de uma transação sai **uma vez**, para quem está conectado naquele instante. Num caso medido, o validador espalhou a transação com **0 sessões** (as conexões ainda estavam subindo). Ao (re)conectar, a réplica reenviava só mensagens de **consenso**, nunca as transações pendentes: o proponente ficou sem a transação para sempre.

## Decisão
1. **O prazo da proposta vale para todos**, inclusive o proponente (como no Tendermint): `start_round` sempre agenda `{:schedule_timeout, :propose, r}`. Se o proponente propõe a tempo, o prazo vence depois e é ignorado (o passo já não é `:propose`); se não, ele **vota nulo** como os demais e o proponente da rodada seguinte tenta.
2. **A réplica reenvia as transações pendentes a quem (re)conecta** (`regossip_pending/2`, no máximo as 256 mais antigas). Quem já tem responde `:duplicate` e nada se repete.

## Consequências
- A vivacidade deixa de depender de a fofoca de uma transação ter chegado a todos no instante certo.
- Nenhuma regra de segurança muda: ninguém assina duas vezes (o diário e `own_vote?` continuam), e o prazo extra só faz o proponente votar **nulo** quando ainda não propôs.
- Custo: até 256 mensagens de transação ao conectar (limitadas pelo canal e pela taxa por sessão).
- **Verificado por mutação:** sem a correção 1, o teste do motor (`propose_timeout_test.exs`) falha; sem a 2, o teste da réplica (`regossip_test.exs`) falha em 4 de 4 rodadas; com as duas, o simulador de equivocação passou **60 de 60** vezes (antes, 1 em 20 travava).

## Alternativas
- **Só a correção 2** (reenviar): corrige este caso, mas qualquer outra falta da transação no proponente (perda, partição, censura) ainda trava a rodada.
- **Só a correção 1** (prazo): a rede se recupera, mas só depois de rodadas de timeout (segundos a dezenas de segundos), e a transação só chega ao proponente certo por sorte.
- **Fazer bloco vazio** para a rodada sempre andar: contraria a decisão de não haver blocos vazios (ADR-0003).
