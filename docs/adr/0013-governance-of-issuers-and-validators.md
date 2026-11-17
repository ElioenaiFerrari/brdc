# ADR-0013 — Governança de emissores e validadores

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
A BRDC é uma stablecoin com consenso BFT autorizado ([ADR-0003](0003-bft-consensus-with-permissioned-validators.md)) e emissores autorizados ([ADR-0002](0002-reserve-backed-by-reais-and-issuers.md)). Falta dizer **quem** são e **como o conjunto muda**. Fecha a pendência P1.

## Decisão
1. **Dois conjuntos separados:** **validadores** (ordenam blocos) e **emissores** (mint, burn, atestado de reserva). Quem opera o consenso não mexe nas reservas, e o contrário também vale.
2. **Quem entra são órgãos** (pessoas jurídicas), definidos na gênese. Pessoas físicas não são validadoras nem emissoras; atuam como **signatárias dentro de um órgão** (M-de-N de credenciais e bens).
3. **Nomear e remover:** um órgão do conjunto propõe; a entrada ou a saída vale com **mais de 2/3 do conjunto em vigor** (do mesmo papel), conferido na validação do bloco. Mesmo desenho da rotação do Teko (ADR-0045).
4. **Travas:** no máximo uma troca pendente; tamanho mínimo e máximo do conjunto; a troca vale só em altura futura.
5. **NPoS não entra agora.** Ele pede um token com valor de mercado, eleição de validadores e slashing de stake. Direção futura: stake **em BRDC** (vale 1 real, sem token volátil), com a regra de entrada reaberta por ADR.

## Alternativas
NPoS/Polkadot desde o início (descartada: complexidade e token volátil); conjunto fixo sem rotação (descartada: um órgão comprometido só sairia recriando a rede).

## Consequências e limites honestos
- Quem nomeia já está dentro: o grupo inicial tende a se perpetuar.
- Mais de 2/3 em conluio controlam o conjunto; mais de 1/3 podem parar a rede.
- Quais órgãos entram na gênese é decisão de implantação, não de código.
