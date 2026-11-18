# Redes

> **Estado:** a **devnet de um validador** roda (`mix phx.server`, com disco). A **rede de vários validadores** (BFT por P2P, com disco e diário) está pronta e testada com 4 validadores em TLS real na mesma máquina ([fluxo 18](flows/18-validator-network.md)); as ferramentas para subir vários nós já existem (`mix brdc.devnet.*`, abaixo); o **roteiro de dois computadores** está escrito e **ensaiado em uma só máquina** ([fluxo 21](flows/21-two-computers.md)); falta rodá-lo em dois computadores de verdade.

## Perfis
| Rede | Para quê | Estado |
|---|---|---|
| `devnet` | Sua máquina: vários validadores como processos OTP | planejado (Fase 3) |
| `testnet` | Vários computadores, dados fictícios, regras iguais às de produção | planejado (Fase 4) |
| `mainnet` | A rede real | **travada**: não existe nesta fase |

## Como será (resumo)
- **Validadores autorizados** com poder igual, bloco final com mais de 2/3 ([ADR-0003](adr/0003-bft-consensus-with-permissioned-validators.md)).
- **Sem blocos vazios:** a cadeia só cresce quando há transação.
- **Duas portas por nó:** a de **pares** (TLS 1.3 mútuo, só validadores) e a **pública** (clientes: carteira, explorador), como no Teko ([ADR-0007](adr/0007-p2p-tcp-with-noise.md)).
- **`chain_id` e hash do genesis** entram no handshake e nas assinaturas: uma rede nunca aceita mensagem de outra.

## Decisões pendentes que afetam as redes
Tempo de bloco, quem são os validadores iniciais e como o conjunto muda (rotação): ver [ADRs pendentes](adr/README.md).

## Rede de teste em dois computadores
Cada computador gera as suas chaves (`mix brdc.keygen`), os dois trocam só os `.pub`, um monta a gênese (`mix brdc.genesis … --peer v1=IP:porta …`) e copia o `genesis.json`, e cada um sobe os seus validadores com `mix brdc.validator --genesis … --seed … --data … --peer-port … --public-port …`. As ferramentas consultam outro computador com `--host IP`, e a carteira com `BRDC_NODE_HOST`. O passo a passo completo, o que foi ensaiado e o que ainda não foi está no **[fluxo 21](flows/21-two-computers.md)**.

## Subir a rede de teste local (vários validadores, tudo por `mix`)
```
mix brdc.devnet.init --validators 4     # (opcional) cria a gênese e as chaves; `up` cria sozinho se faltar
mix brdc.devnet.up                      # sobe os 4 validadores em segundo plano
mix brdc.devnet.status                  # quem está no ar, altura, pendentes, quórum e acordo
mix brdc.fund brdc1… 100                # emite BRDC de teste (qualquer validador serve: porta 4545, 4546…)
mix brdc.devnet.kill 2                  # derruba o validador 2 de repente
mix brdc.devnet.up                      # religa quem caiu; ele se atualiza sozinho
mix brdc.devnet.logs 2 --follow         # acompanha o log do validador 2
mix brdc.devnet.down                    # para todos (os blocos ficam em disco)
mix brdc.devnet.reset                   # apaga blocos, diários, pids e logs (--all: e a gênese, para mudar N)
mix phx.server                          # a carteira acha o validador 1 em 127.0.0.1:4545
```
- **Cada validador é um processo do sistema** (`mix brdc.node --index K`), com pid e log na própria pasta (`net/validators/vK/`). Nenhum bloco nasce sozinho: a rede só cresce quando há transação.
- **Portas:** pares em `4600 + K - 1`, clientes em `4545 + K - 1` (mudam com `--peer-port` e `--public-port` em `devnet.init`). `up` recusa subir se alguma porta estiver ocupada (por exemplo por um `mix phx.server` antigo).
- **O número de validadores é decidido na criação da gênese** e não muda: outro número é outra rede (`devnet.reset --all`).
- **Sem rede gerenciada** (nenhum `devnet.init|up`), o `mix phx.server` continua embutindo um nó solo de 1 validador, como antes.
- **Verificado à mão** com 4 processos reais: mint por um validador chegou aos 4 com o mesmo bloco; `kill -9` em um, os outros 3 decidiram o bloco seguinte; `up` religou o validador, que se atualizou do disco e dos pares; `down` e `up` continuaram da altura anterior com o saldo preservado.

