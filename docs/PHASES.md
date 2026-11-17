# Roteiro das fases

Cada fase só começa com a anterior com testes passando **e documentada**. Ao fim de cada uma: README e fluxos atualizados (texto e diagrama), ADRs, TEST-MATRIX, THREAT-MODEL, GLOSSARY e a seção "como ler o código desta fase" no [guia de conceitos](concepts/README.md).

| Fase | O que entrega | App | Estado |
|---|---|---|---|
| 0 | Fundação: umbrella, qualidade, diagramas, docs-base e ADRs | todos | **em andamento** |
| 1 | Criptografia e carteira: hash etiquetado, Ed25519, BIP-39, SLIP-10, passphrase, endereço, assinatura; vetores oficiais iguais em Elixir e JS | `brdc_crypto` | **pronta** |
| 2 | Livro-razão e a moeda: contas, transação, bloco, estado, transferência, taxa, reservas e mint/burn por emissores M-de-N, invariantes por propriedade | `brdc_ledger` | **pronta** (persistência em disco fica com o ADR-0012) |
| 3 | Consenso BFT: motor sem I/O, rodadas, votos, commit, sem blocos vazios, rotação do conjunto, simulações de falha | `brdc_consensus` | **motor pronto** (rotação do conjunto e WAL com o nó) |
| 4 | P2P: TLS 1.3 mútuo, portas, limites, registros de endereço, descoberta, genesis, roteiro de dois computadores | `brdc_p2p` | **canal seguro, limites, banimento e descoberta prontos** (porta pública, `keygen`/`genesis` e roteiro de dois computadores pendentes) |
| 5 | Contratos nativos: bens e propriedade, credenciais (CNH, identificação, casamento, divórcio), contratos entre partes | `brdc_ledger` | planejado |
| 6 | Carteira web: LiveView + criptografia no navegador, cofre cifrado, enviar e receber, assinar contratos | `brdc_web` | planejado |
| 7 | Explorador, ferramentas e testnet: explorador, mix tasks, simuladores, revisão de segurança, runbook | `brdc_node`, `brdc_web` | planejado |
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

## Decisões que ainda precisam de você
Os ADRs 0010 a 0012 estão **Propostos** (a confirmar) e há decisões **PENDENTES** listadas em [adr/README.md](adr/README.md) (governança inicial de emissores e validadores, tabela de taxas, tempo de bloco e janelas). Nenhuma entra em código antes da sua resposta.
