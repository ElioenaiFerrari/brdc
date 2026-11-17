# BRDC · Brazilian Decentralized Coin

Uma **stablecoin brasileira** (1 BRDC = 1 BRL) numa blockchain própria em **Elixir**, com **contratos nativos** de propriedade, credenciais (CNH, identificação, casamento, divórcio…) e contratos entre partes, uma rede **P2P** de validadores e uma **carteira web não custodial**. Projeto de estudo: sem auditoria, sem validade jurídica, sem integração bancária real.

> **Estado atual: Fase 4 pronta (canal TLS 1.3 mútuo, limites, banimento, descoberta de pares, porta pública, `keygen` e gênese), Fase 3 com o motor de consenso pronto (BFT, simulado com falhas), Fase 2 pronta (ledger em memória: transferência, mint e burn por M-de-N, atestado de reserva, taxas, blocos atômicos).** A Fase 1 também. `brdc_crypto` tem hash etiquetado, Ed25519, BIP-39 com passphrase, SLIP-10, endereços `brdc1…` e codificação determinística, com vetores oficiais conferidos também em JavaScript. **Ainda não há rede P2P, nó rodando nem carteira web**: a moeda e o consenso existem como bibliotecas testadas em memória e por simulação, e o resto chega nas fases seguintes ([roteiro](docs/PHASES.md)).

![Arquitetura da BRDC: a carteira web assina no navegador e envia a transação ao nó, que a coloca no mempool do consenso BFT; o ledger aplica o bloco decidido e os validadores conversam por sessões Noise](docs/diagrams/architecture-overview.png)

## O que a BRDC vai ser

- **Moeda estável em reais.** Emissores autorizados criam (mint) BRDC quando recebem reais e destroem (burn) quando devolvem; as reservas atestadas ficam publicadas na chain. [ADR-0002](docs/adr/0002-reserve-backed-by-reais-and-issuers.md)
- **Consenso BFT** entre validadores autorizados, com finalidade imediata: um bloco decidido não é desfeito. [ADR-0003](docs/adr/0003-bft-consensus-with-permissioned-validators.md)
- **Contratos nativos** (módulos Elixir revisados + modelos declarativos de contrato), sem máquina virtual. [ADR-0004](docs/adr/0004-native-contracts-and-declarative-templates.md)
- **Carteira web não custodial:** as chaves nascem e ficam no navegador (BIP-39, passphrase como 25ª palavra); o servidor nunca as vê. [ADR-0005](docs/adr/0005-keys-ed25519-slip10-bip39.md), [ADR-0006](docs/adr/0006-web-wallet-liveview-and-browser-crypto.md)
- **Rede P2P** em TCP com TLS 1.3 mútuo, autenticada pela chave de cada validador. [ADR-0015](docs/adr/0015-p2p-over-mutual-tls-1-3.md) · [ADR-0007](docs/adr/0007-p2p-tcp-with-noise.md)
- **Sem congelamento de contas** (BRDC sem censura), com os riscos assumidos e documentados. [ADR-0009](docs/adr/0009-no-freezing-uncensored-brdc.md)

## Mapa dos apps (umbrella)

| App | Papel | Fase |
|---|---|---|
| `brdc_crypto` | hash etiquetado, Ed25519, BIP-39, SLIP-10, passphrase, endereços `brdc1…`, codificação determinística (**pronto**) | 1 |
| `brdc_ledger` (moeda pronta) | contas, transações, blocos, estado e módulos nativos (moeda, bens, credenciais, contratos) | 2 e 5 |
| `brdc_consensus` | motor BFT sem I/O: rodadas, votos, certificado de commit | 3 |
| `brdc_p2p` | canal TLS 1.3 mútuo, portas de pares e pública, limites, descoberta | 4 |
| `brdc_node` | nó completo (OTP): supervisão, mempool, armazenamento, RPC | 7 |
| `brdc_web` | carteira LiveView (criptografia em JS no navegador) e explorador | 6 (ainda não criado) |

## Início rápido

```
make setup        # baixa as dependências
make check        # formato, credo e testes
make docs-check   # confere a documentação
make              # lista tudo
```

Para criar uma rede de teste local (as chaves ficam em `net/`, ignorada pelo git; detalhes no [Fluxo 07](docs/flows/07-keygen-and-genesis.md)):

```
mix brdc.keygen v1 && mix brdc.keygen v2 && mix brdc.keygen v3   # validadores
mix brdc.keygen i1 && mix brdc.keygen i2                         # emissores
mix brdc.genesis --chain-id brdc-devnet --validators v1,v2,v3 --issuers i1,i2 --threshold 2
```

Requisitos: Elixir 1.20+ (OTP 29), Node 24 (carteira, Fase 6), Brave (só para gerar os diagramas).

## Por onde começar a ler

1. [Índice da documentação](docs/README.md)
2. [Guia de conceitos](docs/concepts/README.md) (feito para você entender cada peça, com exemplos em Elixir)
3. [Roteiro das fases](docs/PHASES.md) e os [ADRs](docs/adr/README.md)
4. [Arquitetura](docs/ARCHITECTURE.md) e [modelo de ameaças](docs/THREAT-MODEL.md)

## Projeto irmão

O [Teko](../teko) (Rust) é o projeto de estudo de onde vêm os desenhos de BFT, P2P, credenciais e bens. A BRDC os reescreve para Elixir/OTP, com a moeda estável no centro.
