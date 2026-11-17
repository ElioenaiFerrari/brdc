# Fluxo 13 — Criar, proteger e destravar a carteira

## Resumo
A pessoa cria (ou importa) a carteira no navegador. A frase de 24 palavras vira um **cofre cifrado** protegido por uma **senha local**; a **passphrase nunca é guardada**. Ao destravar, o servidor só fica sabendo o **endereço** (público). A carteira bloqueia sozinha por inatividade e ao sair da aba.

## Quem participa
- **Pessoa:** anota a frase, escolhe a senha local e, se quiser, uma passphrase.
- **Hook `Vault`** (`assets/js/vault_hook.js`) e **sessão** (`session.mjs`): fazem tudo que é sensível, no navegador.
- **`WalletLive`** (servidor): recebe só `wallet:unlocked` (com o endereço) e `wallet:locked`.

## Diagramas
Diagrama deste fluxo: **a gerar** (o dono adiou a revisão dos diagramas). O fluxo de assinatura que segue a este está no [Fluxo 12](12-browser-signing.md).

## Passo a passo
**Criar**
1. O navegador gera 24 palavras (entropia do `crypto.getRandomValues`) e as mostra na tela; nada é enviado ao servidor.
2. A pessoa marca que anotou (o botão só habilita depois) e **digita 3 palavras sorteadas** para provar a anotação.
3. Escolhe a senha local (mínimo de 12 caracteres, sem repetição nem só números) e, opcionalmente, a passphrase.
4. O cofre é criado: PBKDF2-HMAC-SHA256 com **600.000 voltas** e sal aleatório derivam uma chave AES-256; o **AES-GCM** cifra `{frase, endereço de criação, usa passphrase?}` com os parâmetros como dado autenticado.
5. O registro (`v`, `kdf`, `iv`, `data`, tudo em hexadecimal) vai para o **IndexedDB**. A tela é limpa (`wipe`) e o endereço vai ao servidor.

**Importar:** igual, a partir de uma frase existente (validada pelo checksum do BIP-39).

**Destravar**
1. Senha local (e a passphrase, se usa) digitadas na hora. O cofre recusa registros com **menos de 600.000 voltas** (rebaixamento) ou valores absurdos.
2. A frase abre; a conta é derivada com a passphrase digitada.
3. Se o endereço derivado **não é o do cofre**, a tela **avisa que é outra carteira** e mostra o endereço, para a pessoa notar uma passphrase errada.
4. A conta fica só na memória da sessão (`createSession`); `sign` é o único uso.

**Bloquear:** botão, 5 minutos sem pointer/teclado, ou a aba ir para segundo plano. A conta sai da memória e o servidor é avisado.

## O que é verificado e por quem
- **Senha errada ou cofre adulterado:** o AES-GCM recusa (sem diferenciar, de propósito). Alterar sal, IV, voltas, versão ou cifra faz falhar.
- **Nada sensível no servidor:** o painel não tem `phx-change`, `phx-submit` nem campo com `name`; `WalletLive` ignora qualquer parâmetro além do endereço e valida o endereço (`Address.decode/1`); o log do Phoenix filtra `password`, `passphrase`, `mnemonic`, `seed`.
- **CSP** sem `unsafe-inline` nem `unsafe-eval` (teste automático).

## O que pode dar errado
- **Senha local fraca + cofre roubado:** o atacante testa senhas offline. Mitigação: 600.000 voltas e 12 caracteres no mínimo; **não é** à prova de senha ruim.
- **Esquecer a senha local não perde os fundos:** a frase recria o cofre. **Esquecer a frase e a passphrase perde tudo.**
- **XSS ou extensão maliciosa com a carteira destravada:** pode assinar ([T16](../THREAT-MODEL.md)).
- **Apagar os dados do navegador apaga o cofre:** só a frase recupera.
- O destravamento leva cerca de 1,5 s por causa das 600.000 voltas (é o custo da proteção).
- Cada origem (endereço e porta) tem seu próprio IndexedDB: abrir a carteira em outro endereço não encontra o cofre.

## Onde está no código
`apps/brdc_web/assets/js/crypto/vault.mjs` (cofre), `store.mjs` (IndexedDB e memória), `session.mjs` (sessão e bloqueio), `assets/js/vault_hook.js` (telas), `lib/brdc_web_web/components/vault_components.ex` (marcação), `lib/brdc_web_web/live/wallet_live.ex` (servidor).

## Testes que cobrem
`vault.test.mjs` (12): senha, 600 mil voltas, cifra sem texto à vista, adulteração de cada campo, rebaixamento, armazenamento, sessão, passphrase não guardada, bloqueio por inatividade. `wallet_live_test.exs` (6): sem campos ligados ao LiveView, só endereço, endereço inválido, parâmetros inesperados, CSP. **Verificado à mão no Chrome 153** (criar com validações, IndexedDB sem texto à vista, servidor recebe só o endereço, bloquear, recarregar, senha errada, passphrase diferente, destravar).

## Limites honestos
- O IndexedDB e o hook de interface **não têm teste automatizado** (precisam de navegador): a verificação foi manual.
- A senha local é a única proteção do cofre em repouso; sem Argon2id ([ADR-0020](../adr/0020-browser-crypto-webcrypto-without-dependencies.md)).
- A passphrase só tem o aviso de "outra carteira" depois de a senha abrir o cofre.
- Ainda **não há** saldo real, envio nem as telas de bens, credenciais e contratos (próximos passos).
