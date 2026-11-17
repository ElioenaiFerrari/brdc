# ADR-0011 — Codificação determinística e hash etiquetado

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
O estado e os blocos precisam ser **idênticos byte a byte** em todos os nós, e o JS da carteira precisa produzir exatamente os mesmos bytes para assinar.

## Decisão
- **Hash:** SHA3-256 com **prefixo de domínio** por uso ("brdc/tx", "brdc/block", "brdc/state", "brdc/addr"…), para que o hash de uma coisa nunca seja aceito como o de outra.
- **Codificação:** **formato próprio, simples e documentado**: campos em ordem fixa, cada um com tipo explícito; inteiros em tamanho fixo (big-endian); bytes e textos com prefixo de tamanho de 4 bytes. Sem CBOR nem Protobuf. **Nunca** `:erlang.term_to_binary` (não é estável entre versões nem é seguro de decodificar).
- A assinatura cobre o `chain_id`, o tipo, o nonce e todos os campos.

## Alternativas
Protobuf (ecossistema bom, mas a canonicidade exige cuidado extra); `term_to_binary` (descartada por segurança e estabilidade).

## Consequências
Um decodificador pequeno e fácil de revisar, igual no JS. Escolha confirmada pelo dono do produto: formato próprio com campos de tamanho definido.
