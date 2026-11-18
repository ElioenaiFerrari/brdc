# Identidade visual e mapa da carteira

A BRDC tem identidade própria: **escura, com as cores do Brasil** (verde, azul, amarelo e branco). **Não é** o tema claro e creme do projeto irmão Teko. Referência de estilo (escolhida pelo dono do produto): carteira fintech moderna com fundo quase preto, brilho suave no topo, cartões escuros de cantos bem arredondados, números grandes com os decimais apagados, botão branco em pílula e teclado numérico. Decisão: [ADR-0022](../adr/0022-visual-identity-and-wallet-scope.md).

## Cores (tokens em `apps/brdc_web/assets/css/app.css`)
| Token | Valor | Uso |
|---|---|---|
| `--brdc-bg` | `#050807` | fundo (quase preto, com tom verde) |
| `--brdc-surface` / `-2` | `#0d1210` / `#131a17` | cartões e áreas internas |
| `--brdc-line` | branco a 8% | bordas finas |
| `--brdc-text` | `#f5f7f6` | texto principal (branco) |
| `--brdc-muted` | `#8fa097` | texto de apoio e decimais |
| `--brdc-green` / `-text` | `#00a651` / `#2bd576` | verde Brasil / verde legível sobre escuro (estados "ok") |
| `--brdc-blue` / `-text` | `#2f6bff` / `#6fa0ff` | azul Brasil / azul legível (privado, informação) |
| `--brdc-yellow` | `#ffdf00` | amarelo Brasil (atenção, pendente, foco do teclado) |

- **Brilho do fundo:** gradientes radiais verde (esquerda) e azul (direita) no topo, com um toque de amarelo. Só no `body`.
- **Contraste:** textos sobre as superfícies têm pelo menos 4,5:1. Cor **nunca** é a única informação: todo chip tem texto (e ícone).
- **Só tema escuro** (um tema daisyUI `brdc`). Tema claro, se existir, será decisão futura.

## Tipografia e forma
- Fontes **do sistema** (`ui-sans-serif`, `system-ui`, …): a CSP não permite fontes de terceiros.
- Números com `tabular-nums`; **centavos apagados** (`<.amount>`); 2 casas na tela (trunca, nunca arredonda para cima) e 6 casas nos detalhes.
- Cantos: cartões `1.5rem`, botões e chips em pílula (`9999px`).

## Componentes (`BrdcWebWeb.BrdcComponents`)
`<.amount>` (valor com centavos apagados), `<.chip>` (estado: neutro, verde, azul, amarelo, com ícone), `<.bottom_nav>` (5 itens, só no celular), `<.keypad>` (teclado numérico), e as classes `.brdc-card`, `.brdc-card-glow`, `.brdc-inset`, `.brdc-btn-primary` (pílula branca), `.brdc-btn-ghost`. Sem JavaScript e sem estilo em linha. Ícones: Heroicons (SVG), nunca emoji.

## Logo
`apps/brdc_web/priv/static/images/mark.svg` (marca) e `logo.svg` (marca + palavra). A marca é uma moeda (disco azul e verde, anel branco) com um **losango amarelo** e um núcleo branco: remete às cores e às formas do Brasil sem copiar a bandeira. Limite: a palavra "BRDC" do `logo.svg` é texto (fonte do sistema), não contorno vetorizado; vetorizar é um passo de acabamento.

## A carteira emite bens, contratos e credenciais
A carteira não é só enviar e receber: é o ponto de entrada de **tudo** que a Fase 5 criou.

| Seção (navegação) | O que a pessoa faz |
|---|---|
| **Início** | saldo, atestado de reserva, **Enviar**, **Receber**, **Emitir**, assinaturas pendentes |
| **Bens** | ver os seus, ofertar, aceitar, finalizar; **órgão**: registrar, vetar, gravames |
| **Contratos** | criar (compra e venda, aluguel, empréstimo), aceitar, pagar parcela, liquidar |
| **Credenciais** | ver as suas (pública ou privada), contestar; **órgão**: emitir, vetar, revogar |
| **Atividade** | histórico das transações e do que está em janela (prazos) |

### Assinatura coletiva (M-de-N)
Registrar um bem, emitir uma credencial, vetar e pôr gravame exigem **várias assinaturas de órgão**, cada uma numa carteira diferente. A carteira trata isso como uma **proposta**:
1. Um membro do órgão **cria a proposta** (o documento que será assinado, mostrado em português).
2. Os outros membros a recebem em **Assinaturas pendentes**, conferem o conteúdo e **assinam no próprio navegador** (a aprovação é `chave ‖ assinatura`).
3. Com M aprovações, qualquer membro **envia** a transação.

A proposta e as aprovações **não têm segredo** (são assinaturas sobre um documento público), então podem circular pela rede ou por um link. Cada assinante **sempre vê o que está assinando**, escrito em texto claro, antes de confirmar. Projeto da tela e do canal: Fase 6 (ainda **planejado**).

## Efeitos de texto e máscara de dinheiro
Tudo em `assets/js/ui_effects.js`, ligado por **atributos** (sem estilo embutido: CSP estrita):
- **`data-decrypt`: texto que se revela ("descriptografando").** Quando o conteúdo do elemento muda (e na primeira aparição), as letras se embaralham em **verde** e se resolvem da esquerda para a direita em até 0,9 s; dígito vira dígito, letra vira letra da mesma caixa, espaços e pontuação ficam no lugar. Usado em saldo, endereço, chip da rede e valores das telas de revisão.
- **`data-scramble-loading`: carregamento.** O texto continua legível e uma parte dos caracteres cintila ("Abrindo a carteira…", "Conectando à rede…"). Nos botões, `loadingLabel` mostra "Descriptografando…", "Criptografando…" ou "Assinando e enviando…" enquanto o trabalho dura.
- **`data-money`: máscara de dinheiro** nos campos de valor (envio, preço de bem, termos de contrato em BRDC).
- **Acessibilidade:** o texto verdadeiro fica sempre disponível a leitores de tela (`.brdc-sr`), os glifos são `aria-hidden`, e quem pede **reduzir movimento** (`prefers-reduced-motion`) vê o texto direto, sem animação.
- A parte sem DOM (quadros do embaralhamento e a máscara) é pura e testada: `crypto/scramble.mjs` e `maskMoney` em `crypto/amount.mjs`.

## Pré-visualização
`mix phx.server` em `apps/brdc_web` e abra `http://localhost:4000/`: mostra a tela **Início** e a tela **Enviar** com dados de exemplo (nada é real).
