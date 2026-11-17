# ADR-0023 — Nó local de um validador e carteira como cliente da porta pública

**Status:** Proposto (aguarda confirmação do dono do produto) · Complementa o [ADR-0007](0007-p2p-tcp-with-noise.md) (duas portas) e o [ADR-0015](0015-p2p-over-mutual-tls-1-3.md).

## Contexto
A carteira precisa de saldo e de um lugar para enviar transações. A rede é P2P: não existe servidor central, e o servidor da carteira **não é um nó**. Também é preciso poder testar tudo numa máquina só.

## Decisão
1. **A carteira (servidor) é cliente** de um nó pela **porta pública em TCP** (`BrdcNode.Client` → `BrdcP2p.PublicPort`), nunca por chamada direta de função. O endereço do nó é configuração (`config :brdc_web, :node`); qualquer nó serve, e o cliente **não confia** nele.
2. **O que cruza a fronteira:** consultas públicas (status, saldo e nonce de um endereço, contratos de um endereço) e **transações já assinadas no navegador**. Nenhum segredo.
3. **Nó local de um validador** (`BrdcNode.Node`): estado do ledger, mempool, blocos **sem blocos vazios**, horário do bloco do relógio (nunca decresce), taxas para a conta do validador, tudo em memória. Com um validador só, o bloco é decidido por ele; ligar o motor BFT e o P2P entre validadores a este nó é o passo seguinte.
4. **Desenvolvimento:** o app `brdc_dev` (fora das entregas de produção) sobe esse nó junto com o resto da umbrella (`mix phx.server` na raiz) e traz `mix brdc.fund` e `mix brdc.balance`. As chaves da rede de teste ficam em `net/` (fora do git).
5. **Valores digitados:** o ponto só vale como separador de milhar bem posicionado; `1.5` é **recusado** (nunca vira 15).

## Alternativas
Carteira chamando o nó por função (descartada: esconde a fronteira e não serve contra um nó remoto); carteira como nó completo no servidor (descartada: o servidor da carteira não deve guardar nem assinar nada).

## Consequências e limites honestos
- **Um nó mentiroso** pode omitir transações, atrasar blocos ou mostrar saldo/nonce/rede falsos. O que protege: a carteira **mostra a rede e o total** antes de assinar, uma transação só vale na rede (`chain_id`) para a qual foi assinada, e saldo ou nonce errados só fazem a transação falhar. Provas de que o saldo é real (certificado de commit, raiz de estado) ainda **não existem**.
- Um validador só: sem tolerância a falhas e sem finalidade distribuída; é um nó de desenvolvimento.
- Estado em memória: reiniciar volta à gênese (ADR-0012 pendente).
- O intervalo entre blocos (`block_interval_ms`) é só um parâmetro (a decisão P3 continua pendente).
