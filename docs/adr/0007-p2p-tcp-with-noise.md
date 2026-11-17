# ADR-0007 — P2P: TCP com Noise vinculado à chave do validador

**Status:** Aceito (dono do produto, 2026-11-17); **o canal foi substituído pelo [ADR-0015](0015-p2p-over-mutual-tls-1-3.md)** (TLS 1.3 mútuo em vez de Noise). Duas portas, limites, banimento e registros de endereço continuam valendo.

## Contexto
Os nós formam uma rede P2P entre participantes que não confiam uns nos outros. Opções: **TCP + Noise feito em Elixir**; distribuição da BEAM sobre TLS; libp2p via processo auxiliar.

## Decisão
**TCP + Noise (handshake XX) em Elixir**, com a chave estática do canal **vinculada à chave de consenso do validador** por uma assinatura dentro do handshake (prova de identidade que inclui o `chain_id` e o hash do genesis). **Duas portas** por nó: a de **pares** (só validadores do conjunto em vigor) e a **pública** (clientes: leitura e envio, com limites). Limites de conexão e taxa, banimento temporário e **registros de endereço assinados** para descoberta.

## Alternativas descartadas
Distribuição da BEAM (qualquer nó conectado executa código no outro: inadequado para quem não confia); libp2p via ponte (outra linguagem, foge do "tudo em Elixir").

## Consequências e limites
- Controle total e fácil de documentar; a escolha da biblioteca Noise (ex.: `decibel`) é revisada na Fase 4.
- A porta pública não é cifrada: o cliente reverifica tudo e não confia no nó.

## Referência
ADR-0048 do projeto Teko (já validado em dois computadores).
