# Decisões de arquitetura (ADRs)

Cada decisão de segurança ou produto vira um ADR: contexto, decisão, alternativas e consequências, inclusive os limites honestos. A regra é **nunca decidir sozinho**: o que não foi decidido pelo dono do produto aparece como **Proposto** ou **PENDENTE**.

| ADR | Título | Status |
|---|---|---|
| [0001](0001-scope-and-goals.md) | Objetivo e escopo da BRDC | Aceito |
| [0002](0002-reserve-backed-by-reais-and-issuers.md) | Lastro em reais e emissores autorizados | Aceito |
| [0003](0003-bft-consensus-with-permissioned-validators.md) | Consenso BFT com validadores autorizados | Aceito |
| [0004](0004-native-contracts-and-declarative-templates.md) | Contratos nativos e modelos declarativos | Aceito |
| [0005](0005-keys-ed25519-slip10-bip39.md) | Chaves: Ed25519, SLIP-10 e BIP-39 com passphrase | Aceito |
| [0006](0006-web-wallet-liveview-and-browser-crypto.md) | Carteira web: LiveView e criptografia só no navegador | Aceito |
| [0007](0007-p2p-tcp-with-noise.md) | P2P: TCP com Noise vinculado à chave do validador | Aceito |
| [0008](0008-fees-paid-in-brdc.md) | Taxas pagas em BRDC | Aceito |
| [0009](0009-no-freezing-uncensored-brdc.md) | Sem congelamento de contas: BRDC sem censura | Aceito, com riscos assumidos |
| [0010](0010-account-model-address-and-decimals.md) | Modelo de conta, endereço e casas decimais | Aceito |
| [0011](0011-deterministic-encoding-and-tagged-hash.md) | Codificação determinística e hash etiquetado | Aceito |
| [0012](0012-state-tree-and-storage.md) | Árvore de estado e armazenamento | **Proposto** |
| [0013](0013-governance-of-issuers-and-validators.md) | Governança de emissores e validadores (P1) | Aceito |
| [0014](0014-fee-table-and-no-halving.md) | Tabela de taxas, repartição e sem halving (P2) | Aceito |

## Decisões PENDENTES (esperam o dono do produto)
Nada abaixo entra em código antes da resposta.

| # | Decisão | Quando precisa |
|---|---|---|
| P1 | ~~Governança inicial~~ → proposta no [ADR-0013](0013-governance-of-issuers-and-validators.md), aceito | Fases 2 e 3 |
| P2 | ~~Tabela de taxas~~ → proposta no [ADR-0014](0014-fee-table-and-no-halving.md), aceito | Fase 2 |
| P3 | **Tempo de agrupamento de blocos** (o intervalo antes de fechar um bloco com transações pendentes) | Fase 3 |
| P4 | **Janelas** de contestação e veto padrão para bens e credenciais | Fase 5 |
| P5 | **Catálogo inicial de contratos entre partes** (compra e venda, aluguel, empréstimo…) e seus parâmetros | Fase 5 |
| P6 | **Biblioteca Noise** em Elixir e **biblioteca de Ed25519 no navegador** (justificar supply chain) | Fases 4 e 1/6 |
| P7 | **Bibliotecas OTP por cenário** (GenStage, Broadway, Flow, Reactor, Benchee, Telemetry…): quais entram, onde e por quê, cada uma com justificativa de supply chain | Fases 2, 3, 4 e 7 |

