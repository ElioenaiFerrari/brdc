# 3. Carteira HD, frase mnemônica e a 25ª palavra

## O problema
Guardar uma chave privada de 32 bytes em papel é difícil e frágil. A solução padrão (BIP-39) é uma **frase de 12 ou 24 palavras** de uma lista fixa de 2048 palavras. Dela se deriva uma **semente**, e da semente **infinitas chaves** (carteira **HD**, hierárquica determinística).

## Da frase à semente (BIP-39)
A semente é `PBKDF2-HMAC-SHA512(frase, "mnemonic" + passphrase, 2048 iterações)`, 64 bytes.

**Roda hoje** (vetor oficial do BIP-39):
```elixir
mn = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
seed = fn pass -> :crypto.pbkdf2_hmac(:sha512, mn, "mnemonic" <> pass, 2048, 64) end
seed.("")       |> Base.encode16(case: :lower)  # começa com 5eb00bbddcf069084889a8ab91555681…
seed.("TREZOR") |> Base.encode16(case: :lower)  # começa com c55257c360c07c72029aebc1b53c05ed…
seed.("") == seed.("x")                          # false
```

## A 25ª palavra (passphrase)
É um texto **opcional**, escolhido por você, somado à frase no `"mnemonic" + passphrase`. Consequências importantes:

- **Outra passphrase = outra carteira inteira**, com outros endereços e outros saldos (acima, `""` e `"TREZOR"` dão sementes totalmente diferentes).
- Quem descobrir só a frase **não** acessa a carteira protegida pela passphrase: é uma segunda camada.
- **Não existe validação:** qualquer passphrase "funciona" e simplesmente abre uma carteira vazia. Digitar errado parece perder tudo (os fundos continuam na carteira certa).
- **Esquecer a passphrase perde os fundos para sempre.** Não há recuperação.
- Permite uma **carteira de fachada**: a frase sem passphrase abre uma carteira com pouco saldo, e a verdadeira só abre com a passphrase.

## Derivação hierárquica (SLIP-10, Ed25519)
Da semente sai uma **chave mestra**; de cada chave se derivam **filhas** por um caminho como `m/44'/…'/0'/0'/0'`. O apóstrofo indica derivação **endurecida** (obrigatória no Ed25519). Assim, uma frase gera quantas contas você quiser, todas recuperáveis. O caminho da BRDC é `m/44'/1112687683'/<conta>'/0'/<índice>'`: `1112687683` é a palavra "BRDC" em ASCII (0x42524443) e **não está registrado no SLIP-44** (provisório). Conta e índice permitem várias contas e vários endereços na mesma frase.

## Endereço
A chave pública Ed25519 vira o endereço `brdc1…` (hash etiquetado `brdc/addr` da chave pública, 32 bytes) em **bech32m**: um prefixo legível, o dado e um **checksum** que detecta erros de digitação.

## Como a BRDC usa
Tudo isso acontece **no navegador** ([ADR-0006](../adr/0006-web-wallet-liveview-and-browser-crypto.md)). O servidor nunca vê frase, passphrase nem chave. A carteira guarda a semente **cifrada pela senha local** (IndexedDB). O JS e o Elixir precisam produzir as mesmas chaves: os **vetores oficiais** de BIP-39 e SLIP-10 rodam nos dois.

## Erros comuns
- Guardar a frase em foto, nuvem ou nota: qualquer vazamento esvazia a carteira.
- Confundir **senha local** (protege o cofre neste navegador) com **passphrase** (faz parte da derivação).

## Onde está no código
Fase 1 pronta: veja [Como ler o código da Fase 1](10-reading-phase-1-code.md). O JS da carteira (Fase 6) reaproveita os mesmos vetores.
