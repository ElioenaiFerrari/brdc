# ADR-0009 — Sem congelamento de contas: BRDC sem censura

**Status:** Aceito (dono do produto, 2026-11-17), com riscos assumidos

## Contexto
O USDC e o USDT permitem que o emissor **congele** contas e bloqueie endereços (ordem judicial, sanções). O dono do produto decidiu que a BRDC **não** terá esse controle.

## Decisão
**Não existe operação de congelamento, bloqueio de conta, estorno ou recuperação.** Os emissores só podem **mint, burn e atestar reservas**; ninguém pode mover fundos de uma conta que não assinou.

## Riscos assumidos (honestos)
- **Fundos roubados ou enviados por engano não podem ser recuperados** por ninguém.
- Uma stablecoin lastreada em reais, sem controle de conformidade, **pode ser inviável para emissores regulados** (risco legal e de reputação para quem guarda as reservas) e atrair uso ilícito.
- A decisão pode ser **revista por novo ADR**; o desenho dos módulos deixa claro onde um controle poderia entrar, mas **ele não existe nem é preparado em código**.

## Consequências
Simplicidade e previsibilidade para o usuário; maior risco para os emissores. Documentado para que ninguém descubra isso tarde.
