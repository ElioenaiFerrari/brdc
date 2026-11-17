# ADR-0021 — O cofre da carteira nunca guarda a passphrase

**Status:** Aceito (dono do produto, 2026-11-17) · Complementa o [ADR-0006](0006-web-wallet-liveview-and-browser-crypto.md) e o [ADR-0020](0020-browser-crypto-webcrypto-without-dependencies.md).

## Contexto
A carteira guarda a **frase de 24 palavras** cifrada num cofre local (IndexedDB), protegido por uma **senha local**. A **passphrase** (25ª palavra) muda a carteira inteira ([conceito 03](../concepts/03-hd-wallet-and-passphrase.md)). Falta decidir se o cofre a guarda.

## Estado
Implementado (cofre sem a passphrase, aviso de "outra carteira" ao destravar) e verificado no navegador.

## Decisão
**Nunca guardar a passphrase.** O cofre guarda só a frase cifrada. A passphrase é **digitada a cada destravamento**, usada para derivar a semente e mantida só na memória da aba. A tela de destravar pede a senha local e, se a carteira usa passphrase, a passphrase.

## Alternativa
Cifrar também a passphrase (ou a semente já derivada) no cofre: mais cômodo, mas quem roubar o cofre e acertar a senha local abre a carteira, e perde-se o segundo fator.

## Consequências e limites honestos
- Cofre roubado + senha local fraca **não** abre uma carteira que usa passphrase.
- Custo de uso: digitar a passphrase a cada vez (como numa Trezor).
- A carteira não consegue dizer se a passphrase está **certa** (qualquer uma gera uma carteira válida): a tela mostra o **endereço resultante** para o usuário reconhecer.
- Se o usuário esquecer a passphrase, os fundos ficam inacessíveis; não há recuperação.
