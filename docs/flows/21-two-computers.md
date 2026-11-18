# Fluxo 21 — Rede de teste em dois computadores

> Diagrama: **a gerar** (diagramas adiados a pedido do dono; foco na implementação).

## Resumo
Quatro validadores em BFT, **dois em cada computador**, montados só com **arquivos**: cada computador gera as próprias chaves, os dois trocam **apenas as chaves públicas**, um deles monta a **gênese** (que lista onde achar cada validador) e a copia para o outro, e cada um sobe os seus com `mix brdc.validator`. Com 4 validadores o quórum é 3: **os dois computadores são necessários** (se um cai, a rede para sem bifurcar e retoma quando ele volta). É um **roteiro de teste**, não produção.

## Quem participa
- **Computador A** (por exemplo `192.168.0.10`): validadores `v1` e `v2`; também guarda as chaves de teste dos **emissores** (`i1`, `i2`) e das **autoridades** (`a1`, `a2`), então é onde se emite moeda de teste.
- **Computador B** (por exemplo `192.168.0.20`): validadores `v3` e `v4`.
- **Os dois** precisam estar na mesma rede (ou alcançáveis) e liberar no firewall só as portas abaixo.

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
Portas: **pares** `4600` (v1), `4601` (v2) em A e `4600` (v3), `4601` (v4) em B; **clientes** (carteira, explorador, ferramentas) `4545` e `4546`. Use uma pasta própria, `testnet/`, para não misturar com a `net/` da rede local.

1. **Chaves (cada computador, só as suas).**
   - A: `for n in v1 v2 i1 i2 a1 a2; do mix brdc.keygen $n --dir testnet; done`
   - B: `for n in v3 v4; do mix brdc.keygen $n --dir testnet; done`
   Cada `NOME.seed` (privada, permissão 0600) **fica onde nasceu**, nunca é copiada.
2. **Troca das chaves públicas.** Copie **só os `.pub`** (por pendrive, `scp`, chat: são públicos): os de B para A (`v3.pub`, `v4.pub`) e os de A para B (`v1.pub`, `v2.pub`, `i1.pub`, `i2.pub`, `a1.pub`, `a2.pub`).
3. **Gênese (em A).** Ela diz quem valida, quem emite e **onde achar cada validador**:
   ```
   mix brdc.genesis --chain-id brdc-testnet --dir testnet \
     --validators v1,v2,v3,v4 --issuers i1,i2 --threshold 2 --authorities a1,a2 --authority-threshold 2 \
     --contest-window 60 --veto-window 60 --min-window 1 \
     --peer v1=192.168.0.10:4600 --peer v2=192.168.0.10:4601 \
     --peer v3=192.168.0.20:4600 --peer v4=192.168.0.20:4601
   ```
   Copie `testnet/genesis.json` para B. A ordem dos validadores define o rodízio dos proponentes.
4. **Subir os validadores** (um terminal cada; em A para v1 e v2, em B para v3 e v4):
   ```
   mix brdc.validator --genesis testnet/genesis.json --seed testnet/v1.seed --data testnet/data-v1 --peer-port 4600 --public-port 4545
   mix brdc.validator --genesis testnet/genesis.json --seed testnet/v2.seed --data testnet/data-v2 --peer-port 4601 --public-port 4546
   ```
   (em B, `v3.seed` e `v4.seed` com as mesmas portas). Cada um imprime o **hash da gênese**: tem de ser **idêntico nos quatro**. Se for diferente, aquele validador não vai entrar na rede (ver "O que pode dar errado").
5. **Usar.** Em A (onde estão as chaves dos emissores): `mix brdc.wallet.new alice --dir testnet`, `mix brdc.reserve 100 --dir testnet --port 4545`, `mix brdc.mint alice 100 --dir testnet --port 4545`, `mix brdc.send alice bob 12,5 --dir testnet --port 4546`.
6. **Conferir do outro lado.** Em B, apontando para A ou para si: `mix brdc.blocks --dir testnet --port 4545` (e `--host 192.168.0.10` para consultar os validadores de A), `mix brdc.blocks 2 --host 192.168.0.10 --port 4545` (o hash do bloco e a conferência do certificado têm de ser **iguais** nos quatro), `mix brdc.balance brdc1… --host 192.168.0.10 --port 4545`, `mix brdc.supply …`.
7. **Carteira e explorador de qualquer um dos dois:** `BRDC_NODE_HOST=192.168.0.10 BRDC_NODE_PORT=4545 mix phx.server` e abra `http://localhost:4000` e `http://localhost:4000/explorer` (com `BRDC_NODE_HOST` o nó solo embutido não sobe).

## O que é verificado e por quem
- **Conexão entre validadores:** TLS 1.3 mútuo com a chave de consenso de cada um; só entra quem está na gênese; `chain_id` e **hash da gênese** entram no aperto de mão, então uma gênese diferente não conversa com a rede.
- **Blocos:** mais de 2/3 dos validadores assinam o mesmo bloco; o cliente confere o certificado (fluxo 20).
- **Sementes:** `mix brdc.validator` recusa semente com permissão aberta (diferente de 0600) e chave que não está na gênese.
- **Ferramentas:** com a gênese presente, nunca geram semente nova em silêncio (não bateria com a gênese); quem pede uma semente que a máquina não tem recebe a mensagem "esta máquina não tem X.seed… nunca é copiada".

## O que pode dar errado
- **Um computador cai (2 de 4):** a rede **para sem bifurcar**: a transação fica pendente (`mix brdc.tx --pending`) e nenhum bloco novo sai; quando o computador volta, retoma do disco, sincroniza e a pendente entra.
- **Gênese diferente em um validador** (por exemplo outro `chain-id`): ele sobe, mas **fica numa ilha**: rede com outro nome, altura 0, sem pares. Sintoma: hash da gênese diferente no log e `mix brdc.balance` mostrando outro `chain_id`. Solução: copiar o `genesis.json` certo e apagar a pasta de dados daquele validador.
- **Firewall ou IP errado:** o validador sobe, mas sem alcançar os pares a rede **não anda** (nenhum bloco sai e a transação fica pendente, igual a "um computador caiu"). Isso **não foi ensaiado** com firewall de verdade; confira o IP da gênese, as portas liberadas e se o outro validador está no ar.
- **Mudar o IP de um computador** exige uma **gênese nova** (o endereço dos pares faz parte do hash): é outra rede. A descoberta por registros assinados (ADR-0048 do Teko) não está portada.
- **Semente copiada para outro computador:** deixa de ser "um validador por máquina" e quebra a premissa de independência; o roteiro não faz isso.
- **Porta pública aberta:** serve consultas e aceita transações já assinadas, com limites por IP; em rede de teste com dados fictícios é aceitável; **não** exponha à internet.

## Onde está no código
`apps/brdc_node/lib/brdc_node/validator.ex` e `apps/brdc_node/lib/mix/tasks/brdc.{keygen,genesis,validator}.ex`; `apps/brdc_dev/lib/brdc_dev/{devnet,net,cli,issuance}.ex` (`--host`, `ensure` sem gerar sementes, `seed!/2`); `config/dev.exs` (`BRDC_NODE_HOST`).

## Testes que cobrem
`validator_test.exs` (3): quatro validadores subidos **só por arquivos** (chaves, gênese e sementes em disco) conectam, uma transação enviada a um deles vira o **mesmo bloco** nos quatro e o certificado fecha contra as chaves **fixadas** da gênese; chave fora da gênese é recusada; arquivos ausentes e semente com permissão aberta dão erro claro. `devnet_files_test.exs` (3): `ensure` não gera sementes quando a gênese existe, `seed!` explica o que fazer, e sem gênese tudo é criado como antes.
**Ensaiado à mão** com **dois diretórios** (`A` com `v1`, `v2`, `i1`, `i2`, `a1`, `a2`; `B` com `v3`, `v4`; só `.pub` trocados), quatro processos `mix brdc.validator` reais: o hash da gênese foi igual nos quatro; `reserve`, `mint` e `send` por A foram vistos por B com o mesmo bloco e certificado conferido; **derrubar B inteiro** parou a rede com a transação pendente e, ao religar, o bloco 4 saiu igual nos dois lados; **gênese com outro `chain-id`** ficou isolada (altura 0 contra 4); a carteira/explorador leu um validador por `BRDC_NODE_HOST`.

## Limites honestos
- **O ensaio foi em UMA máquina** (duas pastas, portas diferentes, `127.0.0.1`). Não foi testado entre **dois computadores de verdade**: faltam firewall, NAT, latência, relógios diferentes e queda de rede de verdade. Esta é a primeira coisa a fazer com um segundo computador; o que aparecer entra aqui.
- **Relógio:** os validadores conferem a hora do bloco contra o próprio relógio (ADR-0016); computadores com relógios muito diferentes vão recusar blocos uns dos outros. Sincronize o relógio (NTP).
- **Sem descoberta de pares:** os endereços são os da gênese.
- **Chaves de teste de emissores e autoridades em texto puro** na pasta `testnet/` do computador A: só para dados fictícios.
- **Quatro validadores em dois computadores não é descentralização:** é o mesmo dono. Serve para testar o protocolo entre máquinas, não a confiança entre instituições.
