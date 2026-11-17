# ADR-0016 — Tempo do bloco e janelas em segundos

**Status:** Aceito (dono do produto, 2026-11-17) · Fecha a pendência P4 (janelas de contestação e veto).

## Contexto
Credenciais e bens têm **janelas** (contestação, veto). Em número de blocos, uma janela poderia nunca terminar, porque a chain não produz blocos vazios ([ADR-0003](0003-bft-consensus-with-permissioned-validators.md)). Em tempo, ela termina sozinha. O dono do produto decidiu por **tempo**, por ser mais previsível.

## Decisão
1. **O cabeçalho do bloco carrega `time`** (segundos, inteiro, Unix). Entra no hash do bloco e na raiz de estado. O ledger usa **só esse valor** como "agora": nunca lê o relógio do nó, então a execução continua pura e idêntica em todos os nós.
2. **Regras de aceitação:** o ledger exige `time >= time do bloco anterior` (não decresce). Os **validadores** só dão prevote se o horário for plausível: não menor que o anterior e **no máximo 15 s à frente** do relógio local. Essa conferência é da camada de consenso (`valid_fn`), fora da execução.
3. **Uma janela vence quando `time do bloco >= prazo`.** Antes disso a transação de finalização é recusada; depois, qualquer parte a envia (a chain não se move sozinha).
4. **Valores padrão (segundos)**, definidos na gênese e ajustáveis por classe de bem ou tipo de credencial dentro de limites: contestação **24 h**, veto **48 h**; mínimo **1 min**, máximo **365 dias**. A rede de teste local usa **60 s** para ser testável.
5. A **validade** das credenciais continua por tipo (CNH e identidade 10 anos; certidões sem validade).

## Alternativas
Janela em blocos (descartada: depende do ritmo de produção, e sem blocos vazios pode não terminar); mediana dos horários dos precommits, como no Tendermint (descartada por ora: mais complexa, e o ganho é pequeno para janelas de horas ou dias).

## Consequências e limites honestos
- O proponente pode deslocar o horário **dentro da margem** (segundos). É irrelevante para janelas de horas, mas fica no modelo de ameaças.
- Se os relógios dos validadores estiverem muito errados, a rede **recusa blocos** e pausa (segurança em vez de vivacidade).
- Um relógio de bloco só avança quando há bloco: o "agora" da chain é o do último bloco.
- Janelas muito curtas (a de teste, 60 s) não devem existir em produção; o mínimo é parâmetro da gênese.
