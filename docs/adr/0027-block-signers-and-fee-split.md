# ADR-0027 — Quem aparece em `signers` do bloco e como a taxa é repartida

**Status:** Proposto (adotado **provisoriamente** na M2 para destravar a rede de vários validadores; aguarda confirmação do dono do produto) · Toca o [ADR-0014](0014-fee-table-and-no-halving.md) (aceito)

## Contexto
O ADR-0014 diz que a taxa do bloco é repartida **entre quem assinou o certificado de commit**, e o ledger guarda `signers` no cabeçalho do bloco. Mas o proponente monta o bloco **antes** de existir certificado, e a raiz de estado do cabeçalho (que inclui o resultado da repartição) é conferida por todos **antes** do voto. Ou seja: `signers` não pode ser o conjunto real de assinantes sem criar um círculo.

## O que foi adotado (provisório)
- No modo de vários validadores, `signers` = **o conjunto de validadores em vigor** (endereços, em ordem), e a taxa é repartida **igualmente entre todos eles**; o resto da divisão vai ao proponente.
- **Quem de fato assinou** fica no **certificado de commit**, gravado ao lado do bloco e conferido por qualquer nó (mais de 2/3, assinaturas, hash). É isso que o explorador mostra como "quem assinou".
- Nada muda no ledger (`Block.apply` e a repartição continuam iguais); no modo de um validador só, `signers` continua `[proposer]`.

## Consequência a ter clara
Um validador **fora do ar** também recebe sua parte da taxa naquele bloco (recompensa por estar no conjunto, não por ter assinado aquele bloco). Com a taxa em BRDC e valores minúsculos, o efeito econômico é pequeno, mas é uma **mudança de sentido** em relação ao texto do ADR-0014.

## Alternativas
1. **Repartir pelo certificado do bloco anterior** (como o Tendermint faz com o `LastCommit`): o bloco H+1 leva o certificado de H e distribui as taxas de H a quem assinou H. Preserva o ADR-0014 ao pé da letra, mas exige mudar o ledger (cabeçalho com o certificado anterior, distribuição adiada) e a conferência no ledger.
2. **Só o proponente leva a taxa** (sem repartir): simples, mas dá incentivo ruim (ninguém quer ser só votante).
3. **Manter o provisório** (esta decisão): simples, determinístico, sem mexer no ledger.

## Recomendação
Manter o provisório agora e, se o dono quiser que a taxa premie **quem assinou**, fazer a alternativa 1 numa etapa própria (mexe no ledger, nos vetores e nos testes).

## Pendente
**Decisão do dono do produto:** aceitar o provisório ou escolher a alternativa 1.
