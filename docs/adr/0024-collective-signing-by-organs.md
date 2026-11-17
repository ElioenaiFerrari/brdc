# ADR-0024 — Assinatura coletiva dos órgãos: propostas no nó, aprovações no navegador

**Status:** Proposto (aguarda confirmação do dono do produto) · Complementa o [ADR-0019](0019-credentials-with-contest-window-and-revocation.md) e o [ADR-0023](0023-local-node-and-wallet-as-client.md).

## Contexto
Emitir uma credencial exige M assinaturas de membros de um órgão, cada um na **própria** carteira, em momentos diferentes. É preciso um lugar onde a proposta espere pelas assinaturas, sem dar poder novo a esse lugar.

## Decisão
1. **A proposta carrega só os campos** (tipo, id, titular, dados, referência). O **documento a assinar é sempre recalculado** pelo nó (`Credentials.issue_doc`) e pelo navegador de cada membro; ninguém assina um documento recebido pronto.
2. **O nó guarda as propostas** (`BrdcNode.Proposals`, puro e em memória, máximo de 200, uma por id de credencial). Cada aprovação (`chave ‖ assinatura`) é conferida contra o órgão do tipo, com chaves distintas; duplicada não conta. Nada ali é segredo (assinaturas sobre documento público).
3. **Porta pública, tipo 6** (`proposta`): propor, aprovar e listar as dos órgãos de uma chave. Consultas novas no tipo 5: credenciais do titular e tipos de que uma chave faz parte.
4. **A emissão final é uma transação comum (tipo 15)**, enviada por qualquer pessoa com saldo para a taxa; o **limite M é do ledger**, não do nó: aprovações a menos são recusadas na execução.
5. **O servidor da carteira recebe a chave pública** junto com o endereço (dado público) para mostrar os órgãos do usuário; só a aceita se bater com o endereço. Nunca recebe chave privada, frase ou senha.
6. **Antes de assinar, a tela mostra os campos por extenso**; credencial privada mostra que só o compromisso vai à rede.

## Consequências
- O nó que guarda propostas pode **recusar-se a repassar** ou **esquecer** (reinício): ninguém perde nada, basta propor de novo. Não pode forjar aprovação.
- Um nó malicioso pode **mostrar campos diferentes dos reais** a um membro; por isso o navegador recalcula o documento a partir dos campos que ele **mostra**, e a assinatura só vale para eles.
- Propostas somem do nó quando a credencial é emitida.

## Pendente
Persistência das propostas em disco (junto do ADR-0012) e propostas para **bens**, **veto** e **revogação**.
