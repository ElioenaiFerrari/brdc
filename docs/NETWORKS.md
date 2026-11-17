# Redes

> **Planejado.** Nenhuma rede existe ainda; este documento fixa o desenho para as Fases 3, 4 e 7.

## Perfis
| Rede | Para quê | Estado |
|---|---|---|
| `devnet` | Sua máquina: vários validadores como processos OTP | planejado (Fase 3) |
| `testnet` | Vários computadores, dados fictícios, regras iguais às de produção | planejado (Fase 4) |
| `mainnet` | A rede real | **travada**: não existe nesta fase |

## Como será (resumo)
- **Validadores autorizados** com poder igual, bloco final com mais de 2/3 ([ADR-0003](adr/0003-bft-consensus-with-permissioned-validators.md)).
- **Sem blocos vazios:** a cadeia só cresce quando há transação.
- **Duas portas por nó:** a de **pares** (Noise, só validadores) e a **pública** (clientes: carteira, explorador), como no Teko ([ADR-0007](adr/0007-p2p-tcp-with-noise.md)).
- **`chain_id` e hash do genesis** entram no handshake e nas assinaturas: uma rede nunca aceita mensagem de outra.

## Decisões pendentes que afetam as redes
Tempo de bloco, quem são os validadores iniciais e como o conjunto muda (rotação): ver [ADRs pendentes](adr/README.md).
