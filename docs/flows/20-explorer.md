# Fluxo 20 — Explorador: ver blocos, transações e contas, inclusive o que está em andamento

> Diagrama: **a gerar** (diagramas adiados a pedido do dono; foco na implementação).

## Resumo
Qualquer pessoa acompanha a rede sem chave nenhuma: os **blocos produzidos** (com quem assinou cada um), as **transações** (valor, origem, destino, taxa, bloco), o **histórico e o saldo de uma conta** e o que está **esperando bloco** agora. Existe na web (`/explorer`, só leitura, atualiza sozinho) e no terminal (`mix brdc.blocks`, `mix brdc.tx`). O ponto central é que cada bloco mostrado vem com a **conferência do certificado de commit**: mais de 2/3 dos validadores assinaram aquele mesmo bloco.

## Quem participa
- **Quem consulta** (pessoa no navegador ou no terminal): não precisa de carteira, senha ou chave.
- **Servidor web / ferramentas:** são clientes da **porta pública** de um nó (`BrdcNode.Client`); nada escrevem.
- **Nó:** responde as consultas a partir do que já tem (blocos, certificados e um índice de transações).

## Diagramas
Diagrama deste fluxo: **a gerar** (diagramas adiados a pedido do dono).

## Passo a passo
**Na web** (`mix phx.server`, depois `http://localhost:4000/explorer`):
1. **Início:** rede, altura, quantas transações pendentes, validadores, oferta em circulação; **Esperando bloco** (o mempool: o que já foi enviado e ainda não entrou) e **Últimos blocos**. Atualiza a cada 1 s com pendências e a cada 3 s parado; a carteira também aparece ligada no menu.
2. **Busca** (um campo só): um **número** abre o bloco daquela altura; **64 caracteres hexadecimais** abrem a transação; um endereço **`brdc1…`** abre a conta. Outra coisa dá um aviso, não um erro.
3. **Bloco:** hash, bloco anterior, hora, quem propôs, raiz de estado, a lista de quem assinou e as transações; navega para o anterior e o próximo.
4. **Transação:** tipo em português (as 21 espécies: transferência, emissão, resgate, atestado, os passos de bens, credenciais e contratos), valor quando há, origem e destino clicáveis, taxa, nonce e o bloco onde entrou.
5. **Conta:** saldo (e com as pendentes, se diferir) e o histórico, do mais novo ao mais antigo, dizendo se enviou ou recebeu.

**No terminal** (rede de teste no ar):
- `mix brdc.blocks` lista os blocos recentes (`--count`, `--before`); `mix brdc.blocks 3` mostra o bloco e **confere o certificado**.
- `mix brdc.tx ID` mostra uma transação; `mix brdc.tx --pending` lista o que espera bloco; `mix brdc.tx --of sim-alice` mostra o histórico de uma conta (nome de carteira de teste ou endereço).

## O que é verificado e por quem
- **O cliente confere o certificado** (`Client.block/3`): é do mesmo bloco (hash e altura), todos os votos são precommits válidos de validadores diferentes, e são **mais de 2/3** do conjunto. Quem não passa aparece como **"Não conferido"** com o motivo, nunca como confiável.
- **Sem fixar as chaves da gênese**, a conferência usa as chaves que o próprio nó informa. Isso prova que o bloco é **consistente por dentro**, não que o nó é honesto; a tela e o terminal dizem isso. Fixando as chaves da gênese (parâmetro `validators` do cliente), a confiança é total.
- A **transação** devolvida pelo nó é reconferida pelo cliente: o id calculado do conteúdo tem de ser o id pedido.
- **Limites nas consultas** (porta pública): no máximo 100 blocos por listagem, 200 itens de histórico ou de pendentes; consulta fora do limite é recusada.
- **Somente leitura:** a página `/explorer` não tem cofre, nem gancho de assinatura, nem envio; a CSP estrita vale para ela também (teste cobre).

## O que pode dar errado
- **Nó mentiroso** (mostra blocos falsos): sem as chaves da gênese fixadas, a conferência é só de consistência. Mitigação: fixar as chaves; consultar vários nós.
- **Nó de um validador só, sem consenso** (o nó embutido de `mix phx.server` sem rede de teste): **não há certificado**; o bloco aparece como "Não conferido" com o texto "rede de um nó só", e é o comportamento certo.
- **Bloco antigo:** o nó só guarda os **últimos 1.000 blocos** na memória (e seus certificados); mais antigo que isso dá "não existe (ou já saiu da memória do nó)", embora esteja no disco. Índice em disco é trabalho futuro.
- **Histórico incompleto:** só entram no histórico o remetente (sempre) e o destinatário de transferência, emissão e resgate; contratos, bens e credenciais aparecem só para quem os enviou. Até 500 entradas por conta (as mais novas).
- **Latência:** pendente que entra e vira bloco em menos de 1 s pode nunca ser vista em "Esperando bloco".
- **Nada privado aqui:** credenciais privadas só têm compromisso na chain; o explorador não as revela e não tem como.

## Onde está no código
`apps/brdc_node/lib/brdc_node/{index,explorer,node,handler,client}.ex` (índice, apresentação, consultas `<<9>>` a `<<14>>` da porta pública e o cliente que confere); `apps/brdc_web/lib/brdc_web_web/{explorer/data.ex,live/explorer_live.ex}` e as rotas em `router.ex`; `apps/brdc_dev/lib/mix/tasks/brdc.{blocks,tx}.ex`.

## Testes que cobrem
`explorer_test.exs` (nó, 10: blocos e paginação, certificado conferido com chaves fixadas e informadas, chaves falsas e quórum fraco **não** conferem, transação por id, histórico dos dois lados, pendentes, índice reconstruído do disco, validadores), `explorer_view_test.exs` (5: nomes dos 21 tipos, encurtadores, dinheiro sem perder precisão, hora, descrição), `explorer_live_test.exs` (10: sem conexão, início, pendente que some ao virar bloco, bloco conferido, nó solo "não conferido", transação, conta, busca, entradas inválidas, somente leitura com CSP). **Verificado à mão no Chrome** contra uma rede de 4 validadores em processos reais: início, bloco 3 conferido com 3 assinaturas, transação encontrada pela busca com taxa `0,001172`, e o **bloco 6 aparecendo sozinho** depois de um envio, sem recarregar. No terminal: lista, bloco, transação, histórico (as duas pontas batem), pendentes e erros claros.

## Limites honestos
- **Não é um explorador público de verdade:** roda no seu computador, ligado a um nó seu; não há hospedagem, domínio nem proteção contra abuso.
- **Contratos, bens e credenciais** ainda não têm páginas próprias; aparecem como transações (tipo e remetente).
- **Sem prova de estado** (árvore esparsa de Merkle): o saldo mostrado é o que o nó diz, sem prova de inclusão. O certificado prova o bloco, não o saldo.
- **Memória:** o índice cresce com as transações e some ao parar o nó (é refeito do disco ao subir).
