# ADR-0015 — Canal P2P: TLS 1.3 mútuo com chave fixada, só OTP

**Status:** Aceito (dono do produto, 2026-11-17) · Substitui o canal do [ADR-0007](0007-p2p-tcp-with-noise.md) (o resto do ADR-0007 continua valendo) · Fecha a parte de rede da pendência P6.

## Contexto
O ADR-0007 escolheu Noise. A única biblioteca Noise em Elixir bem mantida (`decibel`, 1.4.0) tem **um só mantenedor**, existe desde setembro de 2026 e declara não ter auditoria; as outras estão abandonadas ou têm licença duvidosa. O dono do produto não quer depender de uma biblioteca de um mantenedor só. Escrever o handshake nós mesmos seria pior (criptografia de protocolo própria, sem auditoria).

Um **spike** (OTP 29) mostrou que o `:ssl` do OTP faz TLS 1.3 com autenticação dos dois lados usando certificados X.509 autoassinados com **Ed25519** e troca de chaves X25519, sem nenhuma dependência nova.

## Decisão
1. **Canal entre validadores = TLS 1.3 mútuo do OTP** (`:ssl`), apenas `tlsv1.3`, `signature_algs: [:eddsa_ed25519]`, `supported_groups: [:x25519]`.
2. **A chave do certificado é a própria chave de consenso Ed25519 do validador.** O certificado é autoassinado e gerado da semente; não há CA nem nome de domínio. A confiança vem de **a chave pública estar no conjunto de validadores em vigor** ([ADR-0013](0013-governance-of-issuers-and-validators.md)), conferida **dentro do `verify_fun`**, no evento do certificado autoassinado: quem não está no conjunto é recusado no próprio handshake, antes de qualquer dado. (O conjunto é consultado a cada conexão, então a rotação vale sem reiniciar.)
3. **Mensagem `hello` obrigatória** logo depois do handshake, com `chain_id` e hash do genesis: redes diferentes se recusam mesmo com chaves iguais. Um par só é tratado como autenticado **depois do `hello` válido**, porque no TLS 1.3 o cliente pode concluir o `connect` antes de o servidor validar o certificado dele.
4. **Quadros** com tamanho em 4 bytes e **limite máximo** por mensagem; leitura com prazo.
5. **O resto do ADR-0007 vale:** duas portas (pares e pública), limites de conexão e de taxa, banimento temporário, registros de endereço assinados e descoberta.

## Alternativas
- Noise com `decibel` (descartada: um só mantenedor, sem auditoria, API ainda mudando).
- Noise escrito por nós sobre `:crypto` (descartada: criptografia de protocolo própria, sem auditoria).
- Distribuição da BEAM (descartada no ADR-0007: o par executa código no outro).

## Consequências e limites honestos
- Zero dependências externas novas para a rede; o código de protocolo é o do time do OTP.
- Superfície X.509 maior que a do Noise, mas é código muito testado; nós só geramos um certificado e conferimos a chave.
- **Reuso de chave:** a chave de consenso também assina o TLS. Os conteúdos assinados são distintos (no TLS, o conteúdo começa com 64 espaços e um texto fixo; no consenso, um hash etiquetado de 32 bytes), então não há colisão entre usos; ainda assim, é reuso e fica registrado.
- Quem comprometer a chave de consenso de um validador também passa a falar como ele na rede; a rotação (ADR-0013) é a resposta.
- **Armadilha comprovada no spike:** aceitar o evento `selfsigned_peer` sem conferir a chave faz o `valid_peer` nunca disparar e **deixa qualquer um entrar**. Há teste dedicado (intruso, servidor impostor).
- Sigilo adiante: o handshake TLS 1.3 é efêmero (X25519), no mesmo nível do Noise.
- A porta pública continua sem esse canal (clientes não são validadores); o cliente reverifica tudo e não confia no nó.
- A biblioteca de Ed25519 do navegador (parte de P6) continua pendente para a Fase 6.
