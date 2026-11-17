# Como ler o código da Fase 5, parte de credenciais (`brdc_ledger`)

Pré-requisito: [Como ler os bens](13-reading-phase-5a-code.md). Fluxo com diagrama: [Fluxo 10](../flows/10-credentials.md).

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `credentials.ex` | as 6 operações (tipos 14 a 19), os documentos que o órgão assina e as cargas |
| 2 | `state.ex` | acrescenta `cred_types` e `credentials` (com a raiz) e `credential_valid?/3` |
| 3 | `executor.ex` | roteia os tipos 14 a 19 e cobra a taxa mínima |

## Ideias-chave
- **Estados:** `:pending` → `:active`, ou → `:contested`/`:vetoed` (descartada); `:pending`/`:active` → `:revoked`. A entrada nunca é apagada.
- **Janela por tempo:** contestar e vetar **antes** do prazo; ativar **depois** (ADR-0016).
- **Pública x privada:** pública guarda os dados (≤ 512 bytes); privada guarda só o compromisso de 32 bytes. O código só confere o tamanho: a prova de que os dados batem com o compromisso é de quem os recebe.
- **Referência e revogação em cadeia:** o tipo diz `ref_type` e `revokes`. É assim que o divórcio revoga o casamento sem código especial para "divórcio".
- **Validade lida, não executada:** `expires_at` é um número; `valid?/3` compara com o horário que você passar.

## Rode você mesmo
Os testes montam o mundo em `world/0` (tipos `cnh`, `casamento` e `divorcio`) e percorrem cada caminho. O de casamento e divórcio está em `describe "casamento e divórcio"`.

## Limites honestos
Veja o [Fluxo 10](../flows/10-credentials.md): o órgão é a fonte de verdade; privacidade por compromisso simples.
