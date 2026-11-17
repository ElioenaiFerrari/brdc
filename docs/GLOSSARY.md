# Glossário

Termos em ordem alfabética. Termos novos entram aqui no mesmo trabalho que os introduz.

- **25ª palavra (passphrase):** texto opcional que se soma à frase de 12 ou 24 palavras antes de derivar a semente (BIP-39). Outra passphrase gera **outra carteira inteira**; esquecê-la perde os fundos. Ver [carteira HD e passphrase](concepts/03-hd-wallet-and-passphrase.md).
- **Atestado de reserva:** declaração assinada pelos emissores de quanto há em reais guardado. A chain só prova que foi **atestado**, não que é verdade. Ver [stablecoin](concepts/05-stablecoin-and-issuers.md).
- **Bech32m:** formato de endereço com prefixo legível (`brdc1…`) e checksum que detecta erro de digitação.
- **BFT (tolerância a falhas bizantinas):** o consenso funciona mesmo que até 1/3 dos validadores falhe ou aja de má-fé. Ver [consenso BFT](concepts/04-bft-consensus.md).
- **Bloco:** lote de transações com cabeçalho (altura, bloco anterior, raiz de estado, proponente) que, depois de decidido, não muda mais.
- **Burn:** destruição de BRDC por um emissor quando o usuário resgata reais.
- **Certificado de commit:** os votos (precommits) de mais de 2/3 dos validadores que tornam um bloco final.
- **Conta (modelo de conta):** cada endereço tem saldo e um nonce; transferir debita uma conta e credita outra. Alternativa ao UTXO.
- **Credencial:** afirmação sobre um titular emitida por um órgão (CNH, identificação, certidão); pode ser pública ou privada (só um compromisso na chain). Ver [credenciais e bens](concepts/08-credentials-and-assets.md).
- **Determinismo:** o mesmo bloco aplicado ao mesmo estado produz sempre o mesmo resultado, em qualquer máquina.
- **Ed25519:** esquema de assinatura de curva elíptica, rápido e determinístico; nativo no Erlang/OTP.
- **Emissor:** instituição autorizada (em conjunto M-de-N) a criar e destruir BRDC e a atestar reservas.
- **Escrow (custódia condicional):** valor ou bem travado por um contrato até as condições serem cumpridas.
- **Finalidade imediata:** um bloco decidido já é definitivo, sem esperar "confirmações".
- **Hash etiquetado:** hash com um prefixo de domínio (por exemplo "brdc/tx"), para que o hash de uma coisa nunca seja confundido com o de outra.
- **HD (hierárquica determinística):** de uma semente se derivam infinitas chaves por caminho (SLIP-10).
- **M-de-N:** decisão que exige M assinaturas distintas de um conjunto de N membros.
- **Mempool:** fila local de transações válidas esperando entrar num bloco.
- **Mint:** criação de BRDC por um emissor quando o usuário deposita reais.
- **TLS 1.3 mútuo:** canal cifrado em que os dois lados provam ter a chave; na BRDC, a chave do certificado é a chave de consenso do validador (ADR-0015). Ver [P2P e canal seguro](concepts/07-p2p-and-secure-channel.md).
- **Noise:** família de protocolos de handshake; foi a primeira escolha (ADR-0007) e foi trocada pelo TLS 1.3 por falta de biblioteca bem mantida.
- **Nonce (de conta):** contador de transações de uma conta; impede repetição (replay) e fixa a ordem.
- **Proponente:** validador que monta o bloco da rodada (muda a cada rodada).
- **Raiz de estado:** hash que resume todo o estado (todas as contas e contratos) no cabeçalho do bloco.
- **Rodada:** tentativa de decidir um bloco numa altura; se o proponente falha, a rodada seguinte tem outro.
- **SLIP-10:** padrão de derivação hierárquica de chaves para Ed25519.
- **Stablecoin:** moeda cripto cujo valor é atrelado a outra (aqui, 1 BRDC = 1 BRL).
- **Validador:** nó autorizado a votar nos blocos.
- **Veto (janela de):** período em que o órgão pode barrar uma operação pendente (por exemplo, uma transferência de bem).
- **Horário do bloco (`time`):** segundos Unix no cabeçalho; é o único "agora" que o ledger conhece. Janelas vencem por ele (ADR-0016).
- **Passphrase (25ª palavra):** texto opcional que entra na conversão frase → semente (BIP-39); outra passphrase abre outra carteira.
- **SLIP-10:** regra para derivar chaves filhas de uma semente em Ed25519 (só endurecidas).
- **Codificação determinística:** jeito fixo de transformar uma estrutura em bytes, igual em todos os nós e no JS (ADR-0011).
- **Autocustódia (carteira não custodial):** só o usuário guarda as chaves. A frase e a passphrase nascem no navegador e nunca vão para o servidor; ninguém (nem a equipe da BRDC) consegue assinar por ele ou recuperar a conta. Perdeu a frase, perdeu o acesso.
