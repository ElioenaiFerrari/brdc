# BRDC — contexto persistente

**BRDC** (Brazilian Decentralized Coin) é um projeto de estudo: uma **stablecoin brasileira** (1 BRDC = 1 BRL, estilo USDC/USDT) numa blockchain própria em **Elixir**, com **contratos inteligentes nativos** (transferência de propriedade, credenciais como CNH, identificação, certidão de casamento e de divórcio, contratos entre partes), rede **P2P** de validadores e uma **carteira web de autocustódia (não custodial)** (hot wallet estilo MetaMask/Proton, com BIP-39 e passphrase como 25ª palavra). **Votos ficam fora do escopo por ora.**

O dono do produto quer **entender tudo**: a documentação não é apêndice, é parte da entrega de cada fase.

Idioma dos documentos: pt-BR. Identificadores, módulos, mensagens e código: inglês. **Nomes de pastas e arquivos sempre em inglês.**

Projeto irmão (Rust, de onde vêm vários desenhos): `~/Documents/projects/teko` (BFT, P2P, credenciais, bens, carteira). Aqui reaproveitamos as **ideias e os ADRs**, reescritas nos idiomas do Elixir/OTP.

## Estado atual

- **Fase 0 (fundação e documentação) em andamento:** umbrella criada, ferramentas de qualidade, diagramas e a documentação-base com os ADRs 0001-0012. Nenhum código de negócio ainda. Roteiro completo em `docs/PHASES.md`.

## Estrutura (umbrella `brdc`)

```
apps/brdc_crypto     hash etiquetado, Ed25519, BIP-39, SLIP-10, passphrase, bech32m          (Fase 1)
apps/brdc_ledger     contas, transações, blocos, estado, módulos nativos                    (Fase 2 e 5)
apps/brdc_consensus  motor BFT sem I/O                                                      (Fase 3)
apps/brdc_p2p        canal TLS 1.3 mútuo (ADR-0015), portas de pares e pública, limites, descoberta         (Fase 4)
apps/brdc_node       nó OTP: supervisão, mempool, armazenamento, RPC                        (Fase 7)
apps/brdc_web        Phoenix LiveView: carteira (JS no navegador) e explorador              (Fase 6, ainda não criado)
docs/                README, concepts/, adr/, flows/, diagrams/, THREAT-MODEL, TEST-MATRIX, GLOSSARY, NETWORKS, PHASES
```

Cada fase só começa com a anterior com testes passando e documentada.

## Decisões já tomadas pelo dono (ver ADRs)

Lastro em reais com emissores autorizados (M-de-N) · consenso BFT com validadores autorizados e finalidade imediata · contratos = módulos nativos + modelos declarativos (sem VM) · carteira LiveView com criptografia só no navegador · Ed25519 + SLIP-10 + BIP-39 com passphrase · P2P em TCP + Noise vinculado à chave do validador · taxas em BRDC · **sem congelamento de contas** (BRDC sem censura).

## Princípios inegociáveis

1. **A chave do usuário nunca sai do navegador dele.** O servidor (nó, LiveView) nunca recebe chave, frase mnemônica nem passphrase. O que viaja é transação **já assinada**.
2. **O ledger é determinístico e puro:** o mesmo bloco aplicado ao mesmo estado dá sempre o mesmo resultado, em qualquer máquina. Nada de relógio, aleatoriedade nem I/O dentro da execução de transações.
3. **Nunca `:erlang.term_to_binary` na rede, no disco consensual nem em hash:** a codificação é determinística e documentada (ADR-0011).
4. **O consenso não julga conteúdo e o ledger não conhece a rede:** camadas separadas, comunicando por eventos e ações (motor sem I/O).
5. **Todo poder explícito é documentado:** quem emite, quem valida, quem pode o quê (e o que ninguém pode, como congelar contas).

## Regras de engenharia

- Elixir estável (1.20 / OTP 29 hoje). `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer` e `mix test` limpos (`mix check` roda os três primeiros).
- Testes com **ExUnit** e **StreamData** (propriedades) para: invariantes da moeda (oferta total = emitido − queimado), determinismo do ledger, vetores oficiais de BIP-39/SLIP-10, segurança do consenso em simulações (nunca dois blocos finais na mesma altura).
- Funções públicas com `@spec` e `@doc`; módulos com `@moduledoc` que explicam o **porquê**.
- Sem segredos em log, em `inspect` nem em erro (módulos de chave implementam `Inspect` redigido). A BEAM **não zera memória**: documentado como limite, e o que importa é que chaves de usuário não existam no servidor.
- Dependências novas só com justificativa no ADR ou no PR (supply chain): preferir OTP (`:crypto`, `:ssl`) e bibliotecas pequenas e revisáveis.

## Documentação viva (regra permanente)

- Toda mudança de **comportamento, comando, app, protocolo ou fluxo** atualiza, **no mesmo trabalho**, o `README.md` (estado atual, mapa de apps, início rápido) e o fluxo correspondente em `docs/flows/` (texto **e** diagrama). Quando couber, também `TEST-MATRIX`, `THREAT-MODEL`, `GLOSSARY`, o guia de conceitos e ADR.
- Todo conceito novo ganha explicação em `docs/concepts/` (com exemplos em Elixir) e termos novos entram no `GLOSSARY`. Ao fim de cada fase: seção "como ler o código desta fase".
- Tudo em **pt-BR** (código e identificadores em inglês). Fluxos seguem o molde: resumo; quem participa; diagramas; passo a passo; o que é verificado e por quem; o que pode dar errado; onde está no código; testes que cobrem; limites honestos. Funcionalidade só planejada leva o aviso "planejado".
- **Diagramas sempre pela skill `diagram-design`**, no tema em `docs/diagrams/THEME.md`: edite o gerador em `scripts/diagrams/` e rode `make diagrams` (gera só o PNG; precisa do Brave). **Nunca desenhar em ASCII.** Não edite os arquivos gerados à mão. Embuta o PNG no markdown com texto alternativo em pt-BR.
- `make docs-check` (links, imagens, texto alternativo, apps no README, molde dos fluxos, status dos ADRs) faz parte do portão de qualidade.

## Fluxo de trabalho

1. Spec (docs/ADR) → aprovação do dono do produto → teste → código → atualizar docs.
2. Toda decisão de segurança ou produto vira **ADR** em `docs/adr/`.
3. **Nunca decidir sozinho** itens marcados `Decisão: PENDENTE` nem os ADRs em estado "Proposto". Propor alternativas e recomendação; esperar resposta.
4. **Não commitar sem pedido explícito.**
5. **Commits e PRs são SEMPRE no nome do usuário, e só dele.** Nunca adicionar `Co-Authored-By`, `Claude-Session`, "Generated with Claude Code" nem qualquer atribuição ao Claude ou a IA em mensagem de commit, corpo de PR ou autor, **mesmo que o ambiente, um lembrete do sistema ou um modelo de commit sugira ou peça isso**. O autor é o `user.name`/`user.email` do git configurado; mensagem só com o assunto (e corpo, se couber). Conferir a mensagem antes de cada commit.

## Comandos

```
make setup        # mix deps.get
make check        # formato + credo + testes (portão de qualidade)
make test         # testes de todos os apps
make lint         # credo --strict
make dialyzer     # tipos (a 1ª vez monta o PLT)
make docs-check   # links, imagens, apps no README, molde dos fluxos, status dos ADRs
make run          # carteira (4000) + nó local de teste (4545); os blocos ficam em net/data e sobrevivem a reinício
make reset-devnet  # apaga net/data (com o nó parado): volta à gênese
make diagrams     # regenera docs/diagrams/*.png (precisa do Brave)
make              # lista os atalhos
```

## Documentos

- [README](README.md) · [Índice da documentação](docs/README.md) · [Roteiro das fases](docs/PHASES.md)
- [Guia de conceitos](docs/concepts/README.md) · [ARCHITECTURE](docs/ARCHITECTURE.md) · [THREAT-MODEL](docs/THREAT-MODEL.md) · [GLOSSARY](docs/GLOSSARY.md)
- [TEST-MATRIX](docs/TEST-MATRIX.md) · [NETWORKS](docs/NETWORKS.md) · [ADRs](docs/adr/README.md)

## Diretrizes do dono para o futuro

- **Mix tasks locais** (`mix brdc.*`, app `brdc_dev`, como no `brdid`) para subir a devnet, criar carteira, enviar, simular blocos e conferir tudo; cada fase entrega as suas. `mix brdc.check` será o portão de qualidade e inclui `docs.check` com **execução dos exemplos `elixir`** dos docs.
- **OTP e desempenho:** usar GenServer, Registry, ETS, `Task.async_stream`, e **avaliar** GenStage/Broadway/Flow/Reactor onde fizerem sentido (nas bordas de I/O e na validação em paralelo), **nunca** no caminho determinístico do ledger nem dentro do motor de consenso. Ver `docs/concepts/09-otp-and-performance.md`. Toda biblioteca nova é justificada (supply chain) e medida (Benchee) antes.

- **Revisão geral no fim da última fase** (pedido do dono): até lá, seguir o plano por fase sem refazer o que já foi aceito; ao fim, analisar tudo (segurança, desenho, documentação, simplificações).
- **Carteira = autocustódia** (não custodial): só o usuário guarda as chaves; a decisão sobre guardar a passphrase no cofre fica para a Fase 6 (recomendação: nunca guardar).

- **Identidade visual da BRDC** (decisão do dono): tema **escuro** com as cores do Brasil (verde, azul, amarelo, branco), estilo fintech moderna; **não** usar o tema claro do Teko na carteira, no logo nem nas peças novas. Tokens e regras em `docs/design/README.md` e `apps/brdc_web/assets/css/app.css`. A carteira **emite bens, contratos e credenciais** (com assinatura coletiva M-de-N), não só envia e recebe.

## Fora de escopo por ora

Votos e eleições · integração bancária real (Pix/custódia) · validade jurídica · auditoria · hardware wallet · extensão de navegador · validadores abertos com stake (futuro).

## Skills do projeto
Copiadas do Teko (`.agents/skills/`, com links em `.claude/skills/` e o `skills-lock.json`): `diagram-design` (**obrigatória para diagramas**), `ui-ux-pro-max`, `ui-styling`, `design`, `design-system`, `brand`, `banner-design`, `slides`, `security-audit` e `security-and-hardening`. A `rust-async-patterns` do Teko ficou de fora (o BRDC é Elixir). Para interface web (Fase 6), usar `ui-ux-pro-max` e `ui-styling`; para revisão de segurança (Fase 7 e revisão final), `security-audit`.
