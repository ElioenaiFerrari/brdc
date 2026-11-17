# Documentação da BRDC

Tudo em **pt-BR** (código e identificadores em inglês). A regra é a **documentação viva**: cada mudança atualiza a doc no mesmo trabalho. Veja as regras no [CLAUDE.md](../CLAUDE.md).

## Para entender (comece aqui)
- [Guia de conceitos](concepts/README.md): blockchain, estado, hash e assinatura, carteira HD e passphrase, consenso BFT, stablecoin, contratos nativos, P2P com Noise, credenciais e bens. Cada página explica o conceito do zero e mostra como a BRDC o usa.
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

A [arquitetura](ARCHITECTURE.md) dá a visão geral.

## Diagramas
Gerados por código em `scripts/diagrams/` (skill `diagram-design`, tema em [diagrams/THEME.md](diagrams/THEME.md)); `make diagrams` regenera. Nunca ASCII, nunca editar o PNG à mão.
