# Fluxo 15 — Contratos entre partes na carteira

## Resumo
A carteira cria e opera os contratos entre duas pessoas (compra e venda, aluguel, empréstimo). Cada passo é uma transação **assinada no navegador**, depois de uma tela que mostra **em texto claro** o que o contrato faz e **quanto dinheiro se move** (os efeitos vêm das próprias regras do Elixir, não de texto escrito à mão).

## Quem participa
- **Parte A** (vendedor, locador, credor) e **parte B** (comprador, locatário, devedor): cada uma na própria carteira.
- **Servidor da carteira (`WalletLive`):** pergunta ao nó os contratos do endereço e os envia ao navegador.
- **Navegador (`contracts_hook.js` + `crypto/contracts.mjs`):** desenha a lista, calcula o efeito de cada ação, assina e envia.
- **Nó:** executa (`BrdcLedger.Contracts`) e responde à consulta pela porta pública (tipo 5).

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
1. **Lista:** a cada atualização o servidor consulta `contracts_of` (porta pública, consulta tipo 5) e manda ao navegador, **só quando algo muda**, os contratos do endereço (endereços `brdc1…`, números como texto), junto com o horário do último bloco.
2. **Cada cartão** mostra o tipo, o seu papel, a outra parte, o estado (em português), as condições, o dinheiro retido e as **ações disponíveis para o seu papel** no estado atual. Ações cujo prazo ainda não chegou aparecem desabilitadas com "a partir de <data>".
3. **Criar:** escolhe o tipo, informa a outra parte (endereço validado pelo checksum) e as condições (valores em BRDC com parser estrito; prazos em minutos ou dias). A revisão mostra o que acontece ao criar (no empréstimo, o credor **trava o principal**; nos outros, só a taxa).
4. **Agir:** a revisão lista cada movimento de dinheiro, por exemplo "Você deposita 10,000000 BRDC em escrow", "Você recebe … do escrow", "Você paga … direto à outra parte", mais a taxa de contrato (0,01 BRDC) e a rede.
5. Ao confirmar, a chave **não extraível** assina; o navegador envia só a transação pronta (`wallet:submit`), o nó valida e inclui no próximo bloco, e a lista atualiza sozinha para as duas partes.

## O que é verificado e por quem
- **Navegador:** endereço, valores, saldo suficiente (valor travado + taxa) e o texto do efeito.
- **Nó:** a regra de verdade: estado, **ator**, **prazo** e saldo; o que o navegador mostra como disponível é só orientação (`:not_party`, `:bad_state`, `:too_early` voltam como motivo em português).
- **Regras sem duplicação:** `generated/contract_templates.json` é **exportado do Elixir** (`ContractTemplates.export/0`); um teste acusa se ficar desatualizado. O cálculo dos efeitos no JS é conferido contra os valores do Elixir (aluguel: caução x parcelas em aberto).
- **Bytes iguais:** contratos criados e executados no JS têm a mesma assinatura e id que os do Elixir (vetores).

## O que pode dar errado
- **Sem arbitragem:** o desenho protege quem pagou (o escrow volta ao comprador se o prazo vencer sem confirmação), mas se as partes discordam a rede só aplica as regras ([ADR-0017](../adr/0017-initial-contract-catalog.md)).
- **Aceitar um contrato que a outra parte criou com termos ruins:** a revisão mostra preço e prazos; conferir é responsabilidade de quem assina.
- **Nó mentiroso:** pode esconder um contrato ou mostrar estado velho; a ação errada é recusada pelo nó, e a revisão mostra a rede.
- **Id do contrato:** gerado aleatoriamente no navegador (`cv-xxxxxx`); colisão rara recusa com "já existe".
- O horário usado para "disponível a partir de" é o do **último bloco**, que só avança quando há bloco (ADR-0016).

## Onde está no código
`apps/brdc_ledger/lib/brdc_ledger/contract_templates.ex` (modelos e `export/0`), `contracts.ex`; `apps/brdc_node/lib/brdc_node/{node,handler,client}.ex` (consulta); `apps/brdc_web/lib/brdc_web_web/{wallet/chain.ex,live/wallet_live.ex,components/contracts_components.ex}`; `apps/brdc_web/assets/js/{contracts_hook.js,contracts_ui.js,crypto/contracts.mjs,generated/contract_templates.json}`.

## Testes que cobrem
`contracts.test.mjs` (10: modelos do Elixir, **bytes e assinatura iguais** aos do Elixir, expressões, condições, compra e venda, aluguel com caução, empréstimo), `devnet_e2e_test.exs` (criar, aceitar e consultar pela rede em TCP; consulta malformada), `wallet_node_test.exs` (a carteira empurra os contratos ao navegador), `contracts_test.exs` (exportação em dia). **Verificado à mão no Chrome 153 com duas carteiras reais** (`localhost` e `127.0.0.1`): Alice criou uma compra e venda; Bob aceitou (escrow) e confirmou o recebimento; os saldos fecharam (Alice 109,99; Bob 89,98) e o contrato terminou "Concluído".

## Limites honestos
- Só **contratos entre partes** têm tela; **bens** e **credenciais** (que exigem as assinaturas coletivas dos órgãos) ainda não.
- Os prazos digitados são em minutos ou dias (a rede de teste aceita a partir de 1 segundo).
- Sem notificação à outra parte: ela vê o contrato quando abre a carteira (a lista atualiza a cada poucos segundos).
- O hook de interface foi verificado à mão, sem teste automatizado de navegador.
