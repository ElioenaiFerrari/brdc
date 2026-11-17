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

## Fase 2 (pronta, exceto persistência)
| Invariante | Teste |
|---|---|
| Assinatura cobre todos os campos; lixo não decodifica | `ledger_test.exs` (`assinatura e codificação`), `properties_test.exs` |
| Mint e burn só com M-de-N emissores, aprovação não vale para outro valor, referência não repete, só o dono queima | `ledger_test.exs` (`mint e burn por M-de-N`) |
| Replay, nonce fora de ordem, outra rede, saldo insuficiente, taxa baixa (tabela ADR-0014) | `ledger_test.exs` (`transferência`) |
| Bloco atômico, sem bloco vazio, altura/prev_hash/state_root conferidos, taxa repartida entre quem assinou | `ledger_test.exs` (`bloco`) |
| Atestado de reserva: só com M emissores, sequência estritamente crescente, não altera saldos nem oferta, subcobertura não congela | `ledger_test.exs` (`atestado de reserva`) |
| **Oferta = emitido − queimado = soma dos saldos** em sequências aleatórias | `properties_test.exs` |
| Mesmo bloco, mesmo estado, mesma raiz (determinismo) | `properties_test.exs` |

*Fica para depois:* persistência em disco e árvore esparsa (ADR-0012, ainda proposto).

## Fase 3 (motor pronto; gossip, WAL e troca do conjunto ficam para depois)
| Invariante | Teste |
|---|---|
| 4 validadores decidem o mesmo bloco, com certificado de mais de 2/3; mesma semente, mesmo resultado | `consensus_test.exs` (`rede saudável`) |
| Proponente fora do ar: a rodada seguinte decide | `consensus_test.exs` (`falhas`) |
| Sem quórum a rede pausa; partição 2×2 não decide e, ao curar, todos decidem o mesmo bloco | `consensus_test.exs` (`falhas`) |
| Bloco que o ledger recusa nunca é decidido | `consensus_test.exs` (`falhas`) |
| **Nunca dois blocos finais na mesma altura** com até 1/3 bizantino (silencioso ou equivocador), com perda de mensagens | `consensus_test.exs` (propriedade de segurança); estresse manual de 4.800 execuções |
| Todos os honestos decidem sem perda de mensagens | `consensus_test.exs` (propriedade de vivacidade) |
| Voto falso, de estranho, de outra altura ou rede, e proposta de quem não é o proponente ou com hash errado são ignorados | `consensus_test.exs` (`motor isolado`) |
| Equivocação vira evidência; `inspect` não mostra a chave | `consensus_test.exs` (`motor isolado`) |
| Certificado: sem quórum, voto repetido, estranho, assinatura ruim, bloco diferente e outra rede falham | `consensus_test.exs` (`certificado`) |

## Fase 4 (em andamento: canal seguro pronto)
| Invariante | Teste |
|---|---|
| Dois validadores do conjunto conversam e cada um vê a chave do outro | `brdc_p2p/test/brdc_p2p/channel_test.exs` |
| Cliente fora do conjunto e servidor impostor são recusados no handshake | `channel_test.exs` |
| Rede ou genesis diferentes se recusam mesmo com chaves do conjunto | `channel_test.exs` |
| O conjunto é consultado a cada conexão (rotação sem reiniciar) | `channel_test.exs` |
| Quadro gigante é recusado antes de ler o conteúdo; par calado estoura o prazo; separação de quadros | `channel_test.exs` (`limites`) |
| O certificado carrega a chave de consenso e só aceita Ed25519 | `channel_test.exs` (`certificado`) |

*Falta da Fase 4:* limites por IP/chave, banimento, registros de endereço, descoberta, porta pública, `keygen`/`genesis` e o roteiro de dois computadores.

## Planejado por fase
| Fase | Invariantes (a testar) |
|---|---|
| 3 (resto) | Sem blocos vazios (no nó); rotação do conjunto por mais de 2/3; WAL e recuperação |
| 4 (resto) | Limites e banimento; registros de endereço assinados e atualizados; porta pública com limites |
| 5 | Bens: transferência só pelo dono, escrow e veto; credenciais: janela de contestação, validade, veto, revogação, privada vs pública; casamento por cônjuge e divórcio revoga casamento; contratos: só as transições do modelo, valores em escrow conservados |
| 6 | Carteira: frase e passphrase nunca saem do navegador; cofre cifrado; assinatura no navegador aceita pelo nó; CSP sem scripts de terceiros |
| 7 | Explorador mostra quem assinou cada bloco; roteiro de dois computadores validado |

## Limites honestos
Testes automatizados rodam numa só máquina; a rede entre computadores é validada à mão (e anotada aqui) até existir um teste equivalente.
