# Matriz de testes

Invariante → teste que o cobre. Linhas *planejadas* ainda não têm teste: entram com a fase que as implementa. A regra é: **nenhuma invariante de segurança sem teste**.

## Fase 0 (hoje)
| Invariante | Teste |
|---|---|
| Cada app existe e está documentado | `apps/*/test/*_test.exs` (`o app existe e está documentado`) |
| A documentação não tem link quebrado, imagem sem alternativa, app fora do README, fluxo fora do molde nem ADR sem status | `make docs-check` |

## Fase 1 (pronta)
| Invariante | Teste |
|---|---|
| BIP-39: vetores oficiais (entropia → frase; frase → semente com e sem passphrase `TREZOR`); lista com 2048 palavras distintas; checksum, palavra e tamanho inválidos são recusados | `apps/brdc_crypto/test/brdc_crypto/vectors_test.exs` |
| SLIP-10 Ed25519: vetor 1 oficial (mestre e `m/0'`); só caminho endurecido e bem formado | `vectors_test.exs` |
| Bech32m: vetores BIP-350 válidos e inválidos; ida e volta; trocar um caractere é sempre detectado | `vectors_test.exs`, `properties_test.exs` |
| Ed25519: vetor RFC 8032; assinatura só vale para a chave e a mensagem; `verify` nunca levanta exceção com lixo | `vectors_test.exs`, `properties_test.exs` |
| Outra passphrase, conta ou índice dá outro endereço; a mesma dá o mesmo; `inspect` não mostra a semente | `properties_test.exs` (`conta e passphrase`) |
| Codificação determinística: ida e volta; bytes sobrando ou faltando e lixo são recusados sem exceção | `properties_test.exs` |
| **Elixir e JS concordam** (semente, chave pública, endereço, SLIP-10, hash etiquetado) | `shared_vectors_test.exs` (Elixir) e `make js-vectors` (Node), ambos sobre `vectors/crypto.json` |

## Planejado por fase
| Fase | Invariantes (a testar) |
|---|---|
| 2 | Determinismo do ledger (mesmo bloco, mesmo estado, mesmo resultado); oferta total = emitido − queimado (propriedade); saldo nunca negativo; nonce impede replay; só M-de-N de emissores faz mint e burn; taxa cobrada e distribuída |
| 3 | Nunca dois blocos finais na mesma altura (simulação com falhas, partição e proponente bizantino); bloco só final com mais de 2/3; sem quórum a rede pausa; sem blocos vazios; rotação do conjunto por mais de 2/3 |
| 4 | Só validador do conjunto abre sessão; outra rede ou genesis é recusada; quadro adulterado ou repetido não decifra; limites e banimento; registros de endereço assinados e atualizados |
| 5 | Bens: transferência só pelo dono, escrow e veto; credenciais: janela de contestação, validade, veto, revogação, privada vs pública; casamento por cônjuge e divórcio revoga casamento; contratos: só as transições do modelo, valores em escrow conservados |
| 6 | Carteira: frase e passphrase nunca saem do navegador; cofre cifrado; assinatura no navegador aceita pelo nó; CSP sem scripts de terceiros |
| 7 | Explorador mostra quem assinou cada bloco; roteiro de dois computadores validado |

## Limites honestos
Testes automatizados rodam numa só máquina; a rede entre computadores é validada à mão (e anotada aqui) até existir um teste equivalente.
