# ADR-0014 — Tabela de taxas, repartição e ausência de halving

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
O [ADR-0008](0008-fees-paid-in-brdc.md) decidiu taxa em BRDC e deixou a tabela e a repartição pendentes (P2). Como 1 BRDC = R$ 1, as taxas precisam ser minúsculas, mas não zero, por causa do spam.

## Decisão
| Operação | Taxa | Em reais |
|---|---|---|
| Transferência | 0,001 BRDC + 0,000001 BRDC por byte | cerca de R$ 0,0013 |
| Emitir ou revogar credencial | 0,01 BRDC | R$ 0,01 |
| Registrar bem ou classe de bens | 0,05 BRDC | R$ 0,05 |
| Transferir propriedade (cada etapa) | 0,02 BRDC | R$ 0,02 |
| Contrato entre partes (cada transição) | 0,01 BRDC | R$ 0,01 |
| Mint, burn e atestado de reserva | 0 | emissores já são autorizados |

- **Repartição:** 100% da taxa vai para os validadores que assinaram o certificado do bloco, em partes iguais; o resto da divisão vai para o proponente.
- **Sem queima de taxa:** preserva a invariante "oferta total = emitido − queimado".
- **Mempool:** maior taxa primeiro, respeitando o nonce por conta.
- **Parâmetros na gênese;** só mudam por mais de 2/3 dos validadores ([ADR-0013](0013-governance-of-issuers-and-validators.md)). Há limite de bytes e de transações por bloco.
- **Sem halving e sem teto fixo.** Não existe emissão automática: a oferta só muda por mint e burn dos emissores autorizados, acompanhando a reserva em reais. Halving limita emissão automática; aqui ela não existe. Um teto fixo quebraria o lastro.

## Consequências e limites honestos
- A recompensa dos validadores vem **só das taxas**. Com pouco uso, rende pouco; na fase institucional os órgãos arcam com os nós, mas isso importa quando houver validadores abertos (stake).
- Os valores são estimativas de estudo; só uma devnet com carga mostra se estão altos ou baixos.
