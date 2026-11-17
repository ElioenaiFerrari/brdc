# Roteiro das fases

Cada fase só começa com a anterior com testes passando **e documentada**. Ao fim de cada uma: README e fluxos atualizados (texto e diagrama), ADRs, TEST-MATRIX, THREAT-MODEL, GLOSSARY e a seção "como ler o código desta fase" no [guia de conceitos](concepts/README.md).

| Fase | O que entrega | App | Estado |
|---|---|---|---|
| 0 | Fundação: umbrella, qualidade, diagramas, docs-base e ADRs | todos | **em andamento** |
| 1 | Criptografia e carteira: hash etiquetado, Ed25519, BIP-39, SLIP-10, passphrase, endereço, assinatura; vetores oficiais iguais em Elixir e JS | `brdc_crypto` | **pronta** |
| 2 | Livro-razão e a moeda: contas, transação, bloco, estado, transferência, taxa, reservas e mint/burn por emissores M-de-N, invariantes por propriedade | `brdc_ledger` | **pronta** (persistência em disco fica com o ADR-0012) |
| 3 | Consenso BFT: motor sem I/O, rodadas, votos, commit, sem blocos vazios, rotação do conjunto, simulações de falha | `brdc_consensus` | **motor pronto** (rotação do conjunto e WAL com o nó) |
| 4 | P2P: TLS 1.3 mútuo, portas, limites, registros de endereço, descoberta, genesis, roteiro de dois computadores | `brdc_p2p` | **pronta** (canal seguro, limites, banimento, descoberta, porta pública, `keygen` e gênese; o roteiro de dois computadores fica para a Fase 7, com o nó) |
| 5 | Contratos nativos: bens e propriedade, credenciais (CNH, identificação, casamento, divórcio), contratos entre partes | `brdc_ledger` | **pronta** (bens, credenciais e contratos entre partes; sem persistência em disco, ADR-0012) |
| 6 | Carteira web: LiveView + criptografia no navegador, cofre cifrado, enviar e receber, emitir e operar bens, contratos e credenciais (assinatura coletiva) | `brdc_web` | **em andamento:** identidade visual, criptografia do navegador, cofre cifrado e telas de criar, importar e destravar prontos; saldo e envio de BRDC contra um nó local de um validador (Fase 7, primeiro passo); **contratos entre partes na carteira** (criar, aceitar e operar); faltam as telas de bens e credenciais, a assinatura coletiva, o nó com vários validadores e o roteiro de dois computadores |
| 7 | Explorador, ferramentas e testnet: persistência, nó com vários validadores, explorador, mix tasks, simuladores, revisão de segurança, runbook ([plano](PHASE-7-PLAN.md)) | `brdc_node`, `brdc_web` | **em andamento:** M1 (persistência em disco) pronta; faltam M3 (memória de voto), M2 (vários validadores), M4 a M7 |
| Futuro | Stake e validadores abertos, extensão de navegador, Pix/custódia real, votos | | fora de escopo |

## Fase 0 · o que está feito
- Umbrella `brdc` com os apps `brdc_crypto`, `brdc_ledger`, `brdc_consensus`, `brdc_p2p` e `brdc_node` (`brdc_crypto`, `brdc_ledger` e `brdc_consensus` implementados; `brdc_p2p` com o canal seguro; `brdc_node` ainda esqueleto documentado).
- Portão de qualidade: `mix check` (formato, credo estrito, testes) e `make docs-check`.
- Gerador de diagramas no tema do projeto e o diagrama de arquitetura.
- Documentação-base: README, CLAUDE.md, guia de conceitos, arquitetura, glossário, modelo de ameaças, matriz de testes e os ADRs 0001 a 0012.

## Diretrizes do dono para as próximas fases (lembretes)
- **Mix tasks locais para testar (como no `brdid`).** Um app só de desenvolvimento, `brdc_dev`, com tasks `mix brdc.*`, entregues junto com cada fase: `mix brdc.devnet.init|up|down|status|reset|logs`, `mix brdc.wallet.new`, `mix brdc.fund`, `mix brdc.send`, `mix brdc.balance --verify`, `mix brdc.blocks`, `mix brdc.explorer`, simuladores (blocos, equivocação, rotação) e `mix brdc.check` (formato, credo, compilação, testes e `docs.check`). Nunca em release.
- **Exemplos executáveis nos docs.** Os trechos `elixir` do guia marcados como "roda hoje" serão **executados** por `mix brdc.docs.check`, para a documentação nunca mentir.
- **Bibliotecas do ecossistema OTP para desempenho** (GenServer, GenStage, Broadway, Flow, Reactor, `Task.async_stream`, ETS…), escolhidas **onde cada uma cabe** e justificadas uma a uma: ver [OTP e desempenho](concepts/09-otp-and-performance.md). Medir antes de otimizar.

- **Revisão geral no fim.** Ao terminar a **última fase**, o dono pediu uma análise de tudo (segurança, desenho, documentação, o que simplificar ou refazer). Até lá, seguimos o plano por fase, sem refazer o que já foi aceito.

## Decisões que ainda precisam de você
- **ADR-0012** (árvore de estado esparsa e armazenamento em disco) continua **Proposto**.
- **P3:** intervalo de agrupamento de blocos (antes de fechar um bloco com transações pendentes). Entra com o nó (Fase 7).
- **P7:** bibliotecas OTP por cenário, justificadas uma a uma quando cada uma entrar.
