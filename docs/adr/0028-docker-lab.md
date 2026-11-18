# ADR-0028 — Laboratório Docker de vários nós: uma imagem, vários papéis

**Status:** **Aceito** (2026-11-18, ao aprovar o plano) · Complementa o [ADR-0025](0025-block-interval-and-otp-libraries.md)

## Contexto
Os testes da rede de vários validadores rodavam todos os nós **dentro de uma só VM**, com rede em loopback. Isso não mostra como os nós se comportam como **processos separados** (queda, pausa, partição, volta, vários nós, memória e CPU limitadas). O dono pediu um ambiente `docker compose` com validadores e carteiras de recursos limitados, **reaproveitando o mesmo Dockerfile**, para testar o P2P e facilitar o que falta implementar.

## Decisão
- **Uma imagem, um `Dockerfile`, uma release** (`mix release brdc`); o papel do container vem de `BRDC_ROLE` = `validator` | `wallet` | `equivocator`, lido em `config/runtime.exs`. O papel roda como filho supervisionado do app **`brdc_dev`** (já "só desenvolvimento"), então **nenhum código de simulação entra em `brdc_node`**.
- **Base de build e de runtime da mesma distribuição** (a release leva o Erlang): `elixir:1.20.4-otp-29-slim` (Debian 13) e `debian:trixie-slim`. Usuário sem privilégios.
- **Ferramentas de cliente no computador**, não na imagem: `mix brdc.*` com `--host/--port` e `--dir compose/net`. Sem `mix` em tempo de execução.
- **Gênese com os nomes dos serviços** como pares de partida; cada validador monta **só a própria semente** (as dos emissores e autoridades ficam no computador).
- **Recursos limitados por serviço** (CPU, memória, swap igual, processos), `cap_drop: [ALL]`, raiz somente leitura, portas **só em `127.0.0.1`** e diferentes das da rede local. Orçamento padrão (4 validadores + 2 carteiras): **3 CPUs e 2,0 GB** (384 MiB por validador, definido pelo teste de carga: com 192 MiB os validadores morriam por falta de memória entre 100 e 200 tx/s).
- O compose é **gerado por uma função pura** (`BrdcDev.Compose.render/1`), testável sem Docker.

## Consequências
- Ganho: processos, DNS, volumes, reinício e partição de rede independentes; a rede fica viva para a carteira e o explorador; as propriedades de segurança do compose (uma semente por validador, portas só locais, limites em todo serviço) são **conferidas por teste** sem precisar do Docker.
- **Não é produção:** a imagem inclui `brdc_dev` e as chaves são de teste em texto puro. O doc e o `THREAT-MODEL` (T28) dizem isso.
- Limite: um só computador (sem NAT, firewall, latência ou relógios diferentes reais).
- Custo: a primeira build baixa dependências e binários (duas dependências da web vêm do GitHub).

## Alternativas
1. **`mix` dentro da imagem** (como a rede local): mais memória por nó e recompilação; descartada.
2. **Duas imagens** (validador e carteira): mais arquivos e builds para manter; o ganho de tamanho não foi medido e a imagem única já tem 179 MB.
3. **Kubernetes ou orquestração entre máquinas:** fora de escopo.
