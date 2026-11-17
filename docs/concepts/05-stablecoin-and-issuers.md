# 5. Stablecoin e emissores

## O que é uma stablecoin
Uma moeda cripto cujo valor é atrelado a outra. A BRDC mira **1 BRDC = 1 BRL**. Há três jeitos de manter o valor:

| Modelo | Como mantém o valor | Exemplo | Risco |
|---|---|---|---|
| **Lastro em moeda fiduciária** | guarda um real para cada BRDC emitido | USDC, USDT | confiar em quem guarda as reservas |
| Colateral em cripto | trava cripto como garantia e liquida se cair | DAI | oráculos, liquidações, complexidade |
| Algorítmica | regras ajustam a oferta, sem lastro | UST (colapsou) | instabilidade |

A BRDC usa o primeiro ([ADR-0002](../adr/0002-reserve-backed-by-reais-and-issuers.md)).

## Mint e burn
- **Mint:** o usuário deposita R$ 100 numa instituição autorizada (um **emissor**); a instituição cria 100 BRDC para o endereço dele.
- **Burn:** o usuário devolve 100 BRDC; o emissor os **destrói** e paga R$ 100 (por exemplo, por Pix, **fora da chain**).

Para que ninguém sozinho crie moeda, mint e burn exigem **M assinaturas de N emissores** (M-de-N), como os órgãos que usamos no Teko.

## A invariante da oferta
A chain mantém e testa por propriedade: **oferta total = tudo que foi emitido − tudo que foi queimado**, e nenhum saldo é negativo. Isso é verificável por qualquer nó.

## O que a chain NÃO consegue provar
**Que os reais existem.** Os emissores publicam **atestados de reserva** assinados ("temos R$ X guardados"); a chain prova que foram **atestados**, não que são verdadeiros. É o mesmo risco de confiança do USDC/USDT: a mitigação é transparência, auditoria externa e, se um dia houver, regulação. Por isso a BRDC é um projeto de estudo e **não** uma moeda para uso real sem esse arcabouço.

## Sem congelamento
Ao contrário do USDC, a BRDC **não** permite congelar contas ([ADR-0009](../adr/0009-no-freezing-uncensored-brdc.md)). Vantagem: ninguém pode bloquear o seu dinheiro. Custo: **fundos roubados ou enviados por engano não têm recuperação**, e emissores regulados podem achar isso inviável.

## Taxas
Toda transação paga uma taxa em BRDC (por byte e por tipo), repartida entre os validadores ([ADR-0008](../adr/0008-fees-paid-in-brdc.md)). Não há moeda de gás separada.

## Onde está no código
*Planejado (Fase 2: módulos `coin` e `reserve` em `brdc_ledger`).*
