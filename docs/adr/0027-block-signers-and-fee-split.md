# ADR-0027 — Quem aparece em `signers` do bloco e como a taxa é repartida

**Status:** **Aceito** (2026-11-18, pelo dono do produto, com a recomendação abaixo) · Toca o [ADR-0014](0014-fee-table-and-no-halving.md) (aceito)

## Contexto
O ADR-0014 diz que a taxa do bloco é repartida **entre quem assinou o certificado de commit**, e o ledger guarda `signers` no cabeçalho do bloco. Mas o proponente monta o bloco **antes** de existir certificado, e a raiz de estado do cabeçalho (que inclui o resultado da repartição) é conferida por todos **antes** do voto. Ou seja: `signers` não pode ser o conjunto real de assinantes sem criar um círculo.

## O que foi adotado
- No modo de vários validadores, `signers` = **o conjunto de validadores em vigor** (endereços, em ordem), e a taxa é repartida **igualmente entre todos eles**; o resto da divisão vai ao proponente.
- **Quem de fato assinou** fica no **certificado de commit**, gravado ao lado do bloco e conferido por qualquer nó (mais de 2/3, assinaturas, hash). É isso que o explorador mostra como "quem assinou".
- Nada muda no ledger (`Block.apply` e a repartição continuam iguais); no modo de um validador só, `signers` continua `[proposer]`.

## Consequência a ter clara
Um validador **fora do ar** também recebe sua parte da taxa naquele bloco (recompensa por estar no conjunto, não por ter assinado aquele bloco). Com a taxa em BRDC e valores minúsculos, o efeito econômico é pequeno, mas é uma **mudança de sentido** em relação ao texto do ADR-0014.

## Alternativas
1. **Repartir pelo certificado do bloco anterior** (como o Tendermint faz com o `LastCommit`): o bloco H+1 leva o certificado de H e distribui as taxas de H a quem assinou H. Preserva o ADR-0014 ao pé da letra, mas exige mudar o ledger (cabeçalho com o certificado anterior, distribuição adiada) e a conferência no ledger.
2. **Só o proponente leva a taxa** (sem repartir): simples, mas dá incentivo ruim (ninguém quer ser só votante).
3. **Manter a regra atual** (esta decisão): simples, determinístico, sem mexer no ledger.

## Decisão
**Aceita a regra atual** (`signers` = conjunto de validadores; taxa repartida igualmente; quem assinou fica no certificado). Motivos:
- Hoje os validadores são instituições com **poder igual e sem stake**; um incentivo por participação ainda não resolve um problema real.
- A alternativa 1 traz um caso novo e ruim: um validador pode ficar **fora da divisão por atraso de rede**, não por má-fé; e exige mexer no ledger (cabeçalho com o certificado anterior, distribuição adiada), nos vetores e nos testes.
- A regra atual é determinística e não dá o que manipular.

## Evolução futura
Quando houver **stake e validadores abertos**, rever a alternativa 1 (repartir pelo certificado do bloco anterior, como o `LastCommit` do Tendermint) junto com a punição por ausência e por equivocação. Isso é uma nova decisão, com ADR próprio, e muda regra de consenso (só em rede de teste até lá).
