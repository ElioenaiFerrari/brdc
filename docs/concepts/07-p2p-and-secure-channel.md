# 7. P2P e canal seguro

## O problema
Os validadores formam uma rede **ponto a ponto** (P2P), sem servidor central, entre participantes que não confiam uns nos outros. Precisamos de três coisas: saber **quem** está do outro lado, impedir que alguém **escute** ou **adultere** a conversa, e impedir que um estranho **inunde** ou engane a rede.

## TLS 1.3 mútuo: handshake autenticado dos dois lados
**TLS 1.3** é o aperto de mão que protege praticamente toda a internet. No modo **mútuo**, o servidor **e** o cliente apresentam um certificado e provam ter a chave privada dele. Depois do handshake, tudo é cifrado e autenticado (adulterar um byte derruba a sessão), e as chaves de sessão são temporárias (X25519), então vazar uma sessão não revela as outras.

A BRDC usa o TLS 1.3 **do próprio Erlang/OTP** (`:ssl`), mantido pelo time do OTP. Não usamos o Noise, que era a primeira escolha, porque a única biblioteca Noise em Elixir tinha um só mantenedor e nenhuma auditoria ([ADR-0015](../adr/0015-p2p-over-mutual-tls-1-3.md)).

## Vincular o canal à identidade do validador
Normalmente o TLS confia numa autoridade certificadora (CA). Aqui **não há CA**: o certificado é **autoassinado** e sua chave é a **própria chave de consenso Ed25519** do validador. Quem recebe confere, durante o handshake:

- a assinatura do certificado fecha (o par tem a chave privada);
- a chave pública **está no conjunto de validadores em vigor** (senão o handshake é recusado, antes de qualquer dado).

Logo depois vem a mensagem `hello`, com `chain_id` e **hash do genesis**: uma rede nunca aceita mensagem de outra. Só depois de um `hello` válido o par conta como autenticado (no TLS 1.3 o cliente pode terminar a conexão antes de o servidor validar o certificado dele).

## Uma armadilha real
Ao aceitar certificados autoassinados é fácil escrever uma verificação que **deixa qualquer um entrar**: no OTP, se o `verify_fun` simplesmente aceita o evento do certificado autoassinado, o evento seguinte (onde se conferiria a chave) **nunca acontece**. A conferência da chave tem de ficar no próprio evento do certificado autoassinado. Foi o que o nosso teste de intruso pegou.

## Duas portas
| Porta | Quem usa | O que serve |
|---|---|---|
| **Pares** (TLS 1.3 mútuo) | só validadores | consenso, blocos, sincronização, descoberta |
| **Pública** (sem login) | carteira, explorador | ler blocos e estado, enviar transação já assinada; com limites por IP |

O cliente **não confia** no nó: reverifica assinaturas e provas, então um nó mentiroso é detectado, não obedecido.

## Defesas
Teto de conexões (total, por IP, por chave; loopback nunca é banido por IP, [Fluxo 05](../flows/05-limits-and-bans.md)), prazo de handshake, tamanho máximo por tipo de mensagem, taxa por sessão, **pontos por mau comportamento e banimento temporário**, e **registros de endereço assinados** para descobrir onde cada validador está sem editar arquivos.

## Por que não a distribuição da BEAM?
Em Erlang/Elixir, nós conectados por distribuição **executam código uns nos outros**: ótimo entre máquinas suas, inadequado para participantes que não confiam entre si ([ADR-0007](../adr/0007-p2p-tcp-with-noise.md)).

## Onde está no código
Em construção na Fase 4 (`brdc_p2p`). O projeto irmão Teko validou o desenho de duas portas, limites e descoberta em dois computadores (ADR-0048 dele), com Noise em vez de TLS.
