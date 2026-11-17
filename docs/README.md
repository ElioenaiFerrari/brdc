# Documentação da BRDC

Tudo em **pt-BR** (código e identificadores em inglês). A regra é a **documentação viva**: cada mudança atualiza a doc no mesmo trabalho. Veja as regras no [CLAUDE.md](../CLAUDE.md).

## Para entender (comece aqui)
- [Identidade visual e mapa da carteira](design/README.md)
- [Guia de conceitos](concepts/README.md): blockchain, estado, hash e assinatura, carteira HD e passphrase, consenso BFT, stablecoin, contratos nativos, P2P, credenciais e bens. Cada página explica o conceito do zero e mostra como a BRDC o usa.
- [Roteiro das fases](PHASES.md): o que existe, o que vem e em que ordem.
- [Arquitetura](ARCHITECTURE.md): quem fala com quem e por quê.
- [GLOSSARY](GLOSSARY.md): os termos, em ordem alfabética.

## Para decidir e conferir
- [ADRs](adr/README.md): cada decisão de segurança ou produto, com contexto, alternativas e consequências (inclusive as pendentes).
- [THREAT-MODEL](THREAT-MODEL.md): quem pode atacar o quê e o que defende.
- [TEST-MATRIX](TEST-MATRIX.md): invariante → teste que o cobre.
- [NETWORKS](NETWORKS.md): redes de teste e a rede entre máquinas (planejado).

## Fluxos
Um fluxo por funcionalidade (texto e diagrama) em `docs/flows/`, à medida que cada fase é entregue:

- [01 — Da frase ao endereço](flows/01-phrase-to-address.md) (Fase 1)
- [02 — Como um bloco é executado](flows/02-block-execution.md) (Fase 2)
- [03 — Uma rodada de consenso](flows/03-consensus-round.md) (Fase 3)
- [04 — Como dois validadores se conectam](flows/04-secure-channel.md) (Fase 4)
- [05 — Limites e banimento na porta de pares](flows/05-limits-and-bans.md) (Fase 4, em andamento)
- [06 — Como um validador descobre os outros](flows/06-peer-discovery.md) (Fase 4)
- [07 — Como uma rede de teste nasce (keygen e gênese)](flows/07-keygen-and-genesis.md) (Fase 4)
- [08 — Porta pública para carteira e explorador](flows/08-public-port.md) (Fase 4)
- [09 — Transferência de propriedade de um bem](flows/09-asset-trade.md) (Fase 5)
- [10 — Credenciais (CNH, identificação, casamento e divórcio)](flows/10-credentials.md) (Fase 5)
- [11 — Contratos entre partes (compra e venda, aluguel, empréstimo)](flows/11-contracts.md) (Fase 5)
- [12 — Como a carteira assina no navegador](flows/12-browser-signing.md) (Fase 6)
- [13 — Criar, proteger e destravar a carteira](flows/13-wallet-vault.md) (Fase 6)

A [arquitetura](ARCHITECTURE.md) dá a visão geral.

## Diagramas
Gerados por código em `scripts/diagrams/` (skill `diagram-design`, tema em [diagrams/THEME.md](diagrams/THEME.md)); `make diagrams` regenera. Nunca ASCII, nunca editar o PNG à mão.
