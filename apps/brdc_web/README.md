# Carteira web e explorador da BRDC (Fase 6)

Phoenix LiveView com a identidade visual escura da BRDC ([docs/design](../../docs/design/README.md)). **Autocustódia**: a frase, a passphrase e a chave nascem e ficam no navegador; o servidor nunca as vê.

**Estado:** identidade visual, **criptografia do navegador** (sem dependências, testada contra vetores do Elixir), **cofre cifrado** (AES-GCM, passphrase nunca guardada) e as telas de **criar, importar e destravar** a carteira estão prontas e foram verificadas no Chrome. O servidor só recebe o endereço. Faltam saldo e envio contra um nó, as telas de bens, contratos e credenciais, e a assinatura coletiva dos órgãos. Fluxos: [12](../../docs/flows/12-browser-signing.md) e [13](../../docs/flows/13-wallet-vault.md).

```
mix phx.server     # http://localhost:4000 (a carteira) · /design (pré-visualização)
make js-test       # criptografia do navegador (Node 24)
```
