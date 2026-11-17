# 7. P2P e Noise

## O problema
Os validadores formam uma rede **ponto a ponto** (P2P), sem servidor central, entre participantes que não confiam uns nos outros. Precisamos de três coisas: saber **quem** está do outro lado, impedir que alguém **escute** ou **adultere** a conversa, e impedir que um estranho **inunde** ou engane a rede.

## Noise: handshake autenticado
**Noise** é uma família de protocolos de aperto de mão (handshake) que estabelece uma sessão **cifrada e autenticada**. A BRDC usa o padrão **XX**: as duas pontas trocam chaves temporárias e estáticas, derivam chaves de sessão e depois todo quadro é cifrado e tem contador (repetição, adulteração e reordenação falham).

## Vincular o canal à identidade do validador
O Noise sozinho prova que as duas pontas têm **uma** chave, não que são **quem dizem ser**. Então, dentro do handshake, cada validador envia uma **prova**: a chave de consenso dele **assina** a chave Noise da conexão, o `chain_id` e o **hash do genesis**. Quem recebe confere:

- a assinatura fecha com a chave Noise **daquela conexão** (não serve em outra);
- a rede e o genesis são os mesmos (uma rede nunca aceita mensagem de outra);
- a chave de consenso está no **conjunto de validadores em vigor**.

Sem prova válida, nada além do handshake é lido.

## Duas portas
| Porta | Quem usa | O que serve |
|---|---|---|
| **Pares** (Noise) | só validadores | consenso, blocos, sincronização, descoberta |
| **Pública** (sem login) | carteira, explorador | ler blocos e estado, enviar transação já assinada; com limites por IP |

O cliente **não confia** no nó: reverifica assinaturas e provas, então um nó mentiroso é detectado, não obedecido.

## Defesas
Teto de conexões (total, por IP, por chave), prazo de handshake, tamanho máximo por tipo de mensagem, taxa por sessão, **pontos por mau comportamento e banimento temporário**, e **registros de endereço assinados** para descobrir onde cada validador está sem editar arquivos.

## Por que não a distribuição da BEAM?
Em Erlang/Elixir, nós conectados por distribuição **executam código uns nos outros**: ótimo entre máquinas suas, inadequado para participantes que não confiam entre si ([ADR-0007](../adr/0007-p2p-tcp-with-noise.md)).

## Onde está no código
*Planejado (Fase 4, `brdc_p2p`). O projeto irmão Teko já validou este desenho em dois computadores (ADR-0048 dele).*
