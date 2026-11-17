# Carteira web e explorador da BRDC (Fase 6)

Phoenix LiveView com a identidade visual escura da BRDC ([docs/design](../../docs/design/README.md)). **Autocustódia**: a frase, a passphrase e a chave nascem e ficam no navegador; o servidor nunca as vê.

**Estado:** a identidade visual (tema, logo, componentes e uma pré-visualização das telas **Início** e **Enviar**) e a **criptografia do navegador** (`assets/js/crypto`, sem dependências, 18 testes contra vetores do Elixir) estão prontas. Faltam o cofre cifrado, as telas reais e a assinatura coletiva dos órgãos. Fluxo: [12](../../docs/flows/12-browser-signing.md).

```
mix phx.server     # http://localhost:4000 (pré-visualização)
make js-test       # criptografia do navegador (Node 24)
```
