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
| Horário do bloco: vira o `agora` do estado, não decresce, entra no hash e na raiz; plausibilidade (não volta, margem de 15 s) | `ledger_test.exs` (`bloco`) |
| Janelas ficam entre o mínimo e o máximo (parâmetros do ledger e da gênese) | `ledger_test.exs` (`parâmetros`), `genesis_test.exs` |
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

## Fase 4 (pronta, exceto o roteiro de dois computadores, que fica para a Fase 7)
| Invariante | Teste |
|---|---|
| Dois validadores do conjunto conversam e cada um vê a chave do outro | `brdc_p2p/test/brdc_p2p/channel_test.exs` |
| Cliente fora do conjunto e servidor impostor são recusados no handshake | `channel_test.exs` |
| Rede ou genesis diferentes se recusam mesmo com chaves do conjunto | `channel_test.exs` |
| O conjunto é consultado a cada conexão (rotação sem reiniciar) | `channel_test.exs` |
| Quadro gigante é recusado antes de ler o conteúdo; par calado estoura o prazo; separação de quadros | `channel_test.exs` (`limites`) |
| O certificado carrega a chave de consenso e só aceita Ed25519 | `channel_test.exs` (`certificado`) |

| Tetos total, por IP e por chave nunca são ultrapassados (propriedade); liberar devolve a vaga | `limits_test.exs`, `listener_test.exs` |
| Pontos somam até o ban; ban expira; pontos são esquecidos; quadro gigante bane de uma vez | `limits_test.exs` |
| Loopback nunca é banido por IP, mas a chave é; intruso repetido em loopback não derruba ninguém | `limits_test.exs`, `listener_test.exs` |
| Balde de fichas: rajada, recusa, reposição; nunca passa da taxa (propriedade); excesso vira ponto | `limits_test.exs`, `listener_test.exs` |

| Registro de endereço: assinado pelo dono; qualquer campo adulterado invalida; mudar um byte nunca gera outro registro válido (propriedade); host e porta inválidos recusados | `discovery_test.exs` |
| Livro: `seq` maior vence, antigo é recusado, estranho ao conjunto, rede errada e impostor recusados, rotação esquece quem saiu | `discovery_test.exs` |
| Descoberta: registro falso é descartado e o bom guardado; mensagem malformada, lista grande e lixo recusados sem exceção | `discovery_test.exs` |
| **De ponta a ponta:** A só conhece B, descobre C por B e disca para C pelo endereço assinado | `discovery_test.exs` (`de ponta a ponta`) |

| `keygen`: semente com permissão 0600, nunca sobrescreve, nome inválido recusado, semente aberta recusada, semente fora do resultado | `brdc_node/test/brdc_node/keygen_test.exs` |
| Gênese: ida e volta; qualquer campo (e a ordem dos validadores) muda o hash; validações; arquivo adulterado recusado; sem segredo; parâmetros do ledger e do canal derivados; lixo não levanta exceção (propriedade) | `brdc_node/test/brdc_node/genesis_test.exs` |
| Porta pública: só 4 tipos, tamanho por tipo, quadro gigante, tipo desconhecido, teto por IP, taxa, inatividade, handler que falha sem derrubar a conexão | `brdc_p2p/test/brdc_p2p/public_port_test.exs` |

*Fica para a Fase 7:* o roteiro de dois computadores (precisa do nó `brdc_node` rodando).

## Fase 5, parte de bens (pronta)
| Invariante | Teste |
|---|---|
| Classe só com M-de-N das autoridades raiz; janela dentro do limite; id válido; sem autoridade configurada, sem classe | `brdc_ledger/test/brdc_ledger/assets_test.exs` (`classe e registro`) |
| Registro só com M-de-N do órgão da classe; id único; aprovação de um bem não vale para outro dono ou metadado | `assets_test.exs` |
| Negociação: só o dono oferta, só o comprador aceita, escrow sai do saldo, finalização só depois do prazo, cancelamento só antes do aceite | `assets_test.exs` (`negociação`) |
| Veto só do órgão (M-de-N) e só antes do prazo; devolve o escrow; aprovação amarrada a comprador, preço e prazo | `assets_test.exs` (`veto do órgão`) |
| Gravame bloqueia oferta e finalização; aprovação do órgão não se repete (`rev`) | `assets_test.exs` (`gravames`) |
| Taxas: registro e classe 0,05; etapas 0,02; ações do órgão sem mínimo; taxa baixa recusada | `assets_test.exs` (`taxas`) |
| **Saldos + escrow = oferta** e escrow = soma dos negócios aceitos em sequências aleatórias; bloco real reparte as taxas | `assets_test.exs` (`propriedades`, `em bloco`) |
| Autoridades e taxas de bens na gênese (ida e volta, validações, hash) | `brdc_node/test/brdc_node/genesis_test.exs` |

## Fase 5, parte de credenciais (pronta)
| Invariante | Teste |
|---|---|
| Tipo só com M-de-N das autoridades raiz; janela, privacidade e referência válidas; sem autoridade, sem tipo | `brdc_ledger/test/brdc_ledger/credentials_test.exs` (`tipos`) |
| Emissão pelo órgão (M-de-N); nasce pendente; ativa só depois da janela; expira pela validade; tipo sem validade nunca expira | `credentials_test.exs` (`emissão, janela e validade`) |
| Público até 512 bytes; privado exatamente 32 (compromisso); aprovação vale só para aquele titular e aqueles dados | `credentials_test.exs` |
| Contestação só do titular e só na janela; veto M-de-N só na janela; revogação M-de-N definitiva; `cred_id` queimado | `credentials_test.exs` (`contestação, veto e revogação`) |
| Casamento por cônjuge; divórcio exige casamento ativo do mesmo titular e o revoga ao ser ativado; vetado ou contestado não revoga | `credentials_test.exs` (`casamento e divórcio`) |
| Taxas: emissão e revogação 0,01; tipo 0,05; resto sem mínimo | `credentials_test.exs` (`taxas`) |
| **Em qualquer sequência:** ids não se repetem, só ativo é válido, divórcio ativo deixa o casamento revogado | `credentials_test.exs` (`propriedade`) |

## Planejado por fase
| Fase | Invariantes (a testar) |
|---|---|
| 3 (resto) | Sem blocos vazios (no nó); rotação do conjunto por mais de 2/3; WAL e recuperação |
| 7 (inclui o resto da 4) | Roteiro de dois computadores validado |
| 5 (resto) | Contratos entre partes: só as transições do modelo, valores em escrow conservados |
| 6 | Carteira: frase e passphrase nunca saem do navegador; cofre cifrado; assinatura no navegador aceita pelo nó; CSP sem scripts de terceiros |
| 7 | Explorador mostra quem assinou cada bloco; roteiro de dois computadores validado |

## Limites honestos
Testes automatizados rodam numa só máquina; a rede entre computadores é validada à mão (e anotada aqui) até existir um teste equivalente.
