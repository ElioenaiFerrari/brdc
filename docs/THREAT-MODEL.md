# Modelo de ameaças

Primeira versão (Fase 0): o que queremos defender, de quem, e o que ainda **não** defendemos. Cresce a cada fase. Linhas marcadas *planejado* só valem quando a fase correspondente for entregue.

## Quem pode atacar
| Ator | O que pode fazer |
|---|---|
| Usuário malicioso | enviar transações inválidas ou repetidas, tentar gastar o que não tem, spam |
| Nó ou rede maliciosos | mentir sobre blocos ao cliente, inundar, particionar |
| Validador malicioso (até 1/3) | equivocar (votar em dois blocos), censurar, recusar votar |
| Validadores em conluio (mais de 2/3) | decidir qualquer coisa |
| Emissor ou custodiante desonesto | criar BRDC sem reserva, atestar reserva falsa |
| Site ou extensão maliciosos | roubar a frase ou a chave no navegador do usuário (carteira quente) |
| Quem rouba o dispositivo do usuário | acessar o cofre local |

## Ameaças e defesas
| # | Ameaça | Defesa | Limite honesto |
|---|---|---|---|
| T1 | Roubo de chave do usuário pelo servidor | a chave nunca existe no servidor; só transação assinada chega (ADR-0006) | um nó/LiveView adulterado pode servir JS malicioso: CSP estrita e sem scripts de terceiros reduzem, não eliminam *(planejado, Fase 6)* |
| T2 | Repetição de transação (replay) | nonce por conta e identificação da rede na assinatura *(planejado, Fase 2)* | |
| T3 | Fork ou dupla decisão | BFT: bloco só é final com mais de 2/3; sem quórum a rede pausa, não bifurca (ADR-0003) *(Fase 3)* | mais de 2/3 em conluio decide o que quiser |
| T4 | Equivocação de validador | evidência de dois votos assinados em conflito *(Fase 3)*; penalização por stake só no futuro | no começo só há evidência pública, sem multa |
| T5 | Criação de moeda sem lastro | só M-de-N de emissores faz mint, com atestados de reserva públicos e invariante de oferta (ADR-0002) *(Fase 2)* | **a chain não prova o lastro real**: confia nos emissores |
| T6 | Spam de transações | taxa em BRDC por byte e por tipo, limites de mempool (ADR-0008) *(Fases 2 e 4)* | |
| T7 | Nó estranho na rede de validadores | canal TLS 1.3 mútuo com a chave do validador fixada no handshake, limites e banimento (ADR-0015, ADR-0007) *(Fase 4)* | a porta pública não é cifrada |
| T8 | Phishing da frase ou da passphrase | a UI nunca pede a frase a ninguém além do próprio cofre local e avisa; BIP-39 com passphrase *(Fase 6)* | usuário enganado entrega a frase: sem recuperação |
| T9 | Fundos roubados ou enviados por engano | **nenhuma**: não há congelamento nem estorno (ADR-0009) | decisão assumida do dono do produto |
| T10 | Corrupção do estado por bug de execução | ledger puro e determinístico, testes por propriedade, raiz de estado no cabeçalho *(Fase 2)* | sem auditoria externa |
| T11 | Divergência entre carteira (JS) e nó (Elixir) na derivação de chaves | vetores oficiais de BIP-39/SLIP-10 e o `vectors/crypto.json` conferidos em Elixir e JS (`make js-vectors`) | o JS de referência é Node; a biblioteca final do navegador (P6) terá de passar nos mesmos vetores |
| T12 | Proponente manipula o horário do bloco para encurtar ou alongar uma janela | horário não decresce (ledger) e só passa se estiver até 15 s à frente do relógio dos validadores (ADR-0016) | desvio de segundos é possível; irrelevante para janelas de horas |
| T13 | Órgão de uma classe comprometido (M assinaturas) registra bens falsos ou veta negociações à vontade | aprovações M-de-N, `rev` impede reaproveitar aprovação, documento do veto amarra comprador, preço e prazo (ADR-0018) | **a chain não sabe se o bem existe**: confia no órgão; sem arbitragem |

## O que este modelo **não** cobre ainda
Privacidade das credenciais privadas em detalhe, governança de emissores e validadores (decisão pendente), ataques de rede em escala (eclipse, partição longa), segurança do navegador do usuário, conformidade legal.
