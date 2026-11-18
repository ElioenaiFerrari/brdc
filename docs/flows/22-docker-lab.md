# Fluxo 22 — Laboratório Docker: vários nós, com recursos limitados

> Diagrama: **a gerar** (diagramas adiados a pedido do dono; foco na implementação).

## Resumo
Uma rede de teste inteira dentro do Docker: **4 validadores e 2 carteiras** (ou N e M, à escolha), cada um num container, com **CPU, memória e processos limitados** para não travar o computador. Todos usam **a mesma imagem** (um só `Dockerfile`, uma release do Elixir); o papel de cada container vem da variável `BRDC_ROLE`. Serve para ver como os nós se comportam no P2P (queda, pausa, partição, volta, vários nós) sem precisar de vários computadores. É **laboratório de teste**: a imagem inclui `brdc_dev` e chaves de teste e **não é produção**.

## Quem participa
- **Validadores** (`v1`…`vN`): papel `validator`; cada um monta só o `genesis.json` e a **própria** semente.
- **Carteiras** (`wallet1`…`walletM`): papel `wallet` (a web LiveView + explorador); cada uma fala com um validador diferente, em rodízio, para ver o dado cruzando nós.
- **Equivocador** (`equivocator`, perfil `byzantine`): papel `equivocator`; só existe com 4 ou mais validadores e só roda sob demanda (fluxo [23](23-equivocation.md)).
- **Você, no computador:** as ferramentas `mix brdc.*` falam com os validadores pelas portas que o Docker publica; as chaves dos emissores ficam só aqui.

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
```
mix brdc.compose.init            # chaves de teste, gênese, docker-compose.yml, .env (pasta compose/, ignorada pelo git)
mix brdc.compose.init --interval 200ms   # (opcional) espera do validador depois da primeira transação para agrupar a rajada no bloco; padrão 1s (`BRDC_INTERVAL_MS`)
mix brdc.compose.up              # build da imagem (1ª vez demora), sobe tudo e espera os validadores
mix brdc.compose.status          # por validador: altura, pares, motor de consenso, evidências, pendentes
mix brdc.compose.down [--volumes]
```
Opções da `init`: `--validators 4`, `--wallets 2`, `--cpus 0.5`, `--memory 384m`, `--wallet-memory 256m`, `--base-port 4700`, `--wallet-port 4100`, `--dir compose`. O número de validadores é decidido na gênese e não muda (outro número é outra rede: apague a pasta).

**Usar** (as ferramentas do host apontam para o laboratório com `--dir compose/net --port 4700`):
```
mix brdc.wallet.new alice --dir compose/net
mix brdc.reserve 1000 --dir compose/net --port 4700
mix brdc.mint alice 500 --dir compose/net --port 4700
mix brdc.send alice bob 12,5 --dir compose/net --port 4702
mix brdc.blocks 2 --dir compose/net --port 4701      # o mesmo bloco em todos
```
**Carteira e explorador no navegador:** `http://localhost:4100` (ligada a `v1`) e `http://localhost:4101` (ligada a `v2`); o explorador em `/explorer` de cada uma.

**Caos** (receitas; o nome do container é `brdc-lab-<serviço>-1` e a rede `brdc-lab_brdc`):
- parar de repente: `docker compose -f compose/docker-compose.yml kill v2`; religar: `start v2`.
- congelar: `pause v3 v4` / `unpause v3 v4` (o processo congela, mas as conexões ficam abertas, então os pares ainda contam o nó como conectado).
- partição: `docker network disconnect brdc-lab_brdc brdc-lab-v4-1` / `connect`.
- desligar de verdade: `stop v4` (as conexões fecham e os pares veem a queda).

## Recursos (para não travar a máquina)
Por container: `cpus` 0,5, memória **384 MiB** (validador) ou 256 MB (carteira), `memswap_limit` igual (sem swap), `pids_limit` 256, `init: true`, `cap_drop: [ALL]`, `no-new-privileges`, raiz somente leitura com `tmpfs: /tmp`. `ERL_AFLAGS="+S 2:2 +A 8 +sbwt none"` impede o BEAM de abrir um escalonador por núcleo do computador dentro de 0,5 CPU; `RELEASE_DISTRIBUTION=none` dispensa a distribuição do Erlang. **Orçamento padrão (4 + 2): até 3 CPUs e 2,0 GB.** Portas só em `127.0.0.1` e diferentes das da rede local (`4545` e `4000`): os dois ambientes rodam juntos. Cada validador tem um volume próprio (os blocos sobrevivem a `stop` e `kill`).

## O que é verificado e por quem
- **Os próprios validadores** (BFT, certificado de mais de 2/3, TLS mútuo com a chave de consenso): o laboratório não muda nada disso, só os coloca em containers.
- **O gerador do compose é testado sem Docker** (função pura): todo serviço tem limite de CPU, memória e swap; a base limita processos; portas só em `127.0.0.1` e a de pares (4600) nunca é publicada; cada validador monta **só a própria semente** (nunca a de outro nem as de emissor e autoridade); carteiras em rodízio e sem semente; reinício, healthcheck e endurecimento presentes.
- **O Docker valida o YAML** (`docker compose config`).

## O que pode dar errado
- **Primeira build lenta e com rede:** baixa a imagem do Elixir, dependências e os binários do Tailwind e do esbuild; duas dependências da web vêm do GitHub.
- **Memória:** o pico medido por validador foi ~135 MiB a 50 tx/s, ~190 a 200, ~215 a 400 e ~290 a 800. Com **192 MiB os validadores morreram por falta de memória (OOM, código 137)** entre 100 e 200 tx/s, todos juntos, porque todos guardam o mesmo mempool; por isso o padrão é 384 MiB. Reduzir o limite faz o Docker matar o container.
- **`pause` engana a contagem de pares** (conexões continuam abertas); para ver a queda, use `stop` ou `kill`.
- **Portas ocupadas:** se `4700+` ou `4100+` estiverem em uso, escolha outras com `--base-port` e `--wallet-port`.
- **Semente montada:** a imagem roda sem root e lê a semente (0600) montada do computador; funcionou no OrbStack. Em outros ambientes pode haver diferença de dono; se acontecer, o validador não sobe e o log diz "semente com permissão aberta" ou falta de acesso.
- **Mudar o número de validadores** exige apagar a pasta `compose/` (outra gênese).

## Onde está no código
`Dockerfile`, `.dockerignore`; `mix.exs` (release `brdc`); `config/runtime.exs` (`BRDC_ROLE`, `BRDC_NODE_*`, `BRDC_ALLOWED_ORIGINS`); `apps/brdc_dev/lib/brdc_dev/{compose.ex,compose/runner.ex,compose/byzantine.ex,application.ex,devnet.ex}`; tarefas `apps/brdc_dev/lib/mix/tasks/brdc.compose.{init,up,down,status,equivocate}.ex`; a consulta de consenso `<<15>>` em `apps/brdc_node/lib/brdc_node/{handler,client}.ex`.

## Testes que cobrem
`compose_test.exs` (10: serviços, limites, portas, sementes, carteiras, endurecimento, equivocador), `compose_init_test.exs` (5: chaves, gênese com os nomes dos serviços, permissões 0600, idempotência, recusa de outro N). Consulta de consenso: `validator_test.exs`. **Verificado à mão** no OrbStack (Docker 29): build da imagem (**179 MB**); 4 validadores e 2 carteiras saudáveis com 3 pares cada; emissão e envio pelo host vistos em **todos os 4 validadores com o mesmo bloco e certificado conferido**; a carteira dentro do container (ligada ao `v2`) mostrou o saldo de uma emissão enviada ao `v4`; `pause` de 2 de 4 parou a rede **sem bifurcar** (`h5 r0 prevote`, 1 pendente) e `unpause` retomou; `kill` de 1 deixou os outros 3 andando e ele voltou do volume e se atualizou; **30 transferências em 51 s** com pico de **3,7% de CPU** (teto 50%) e **135 MB** de memória.

## Limites honestos
- **Um só computador:** o Docker dá processos, DNS, discos, reinício e partição de rede separados, mas **não** dá NAT, firewall, latência e perda de pacote reais, nem relógios diferentes. Latência e perda podem ser emuladas com `tc netem` (não está pronto na imagem).
- **Não é produção:** a imagem inclui `brdc_dev` (ferramentas de teste) e as chaves são de teste, em texto puro em `compose/net`.
- **Sem descoberta de pares:** os endereços são os nomes de serviço da gênese.
- **`docker compose` único:** não é Kubernetes nem orquestração entre máquinas.
