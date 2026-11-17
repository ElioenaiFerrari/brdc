# ADR-0010 — Modelo de conta, endereço e casas decimais

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
Detalhes de base que o dono ainda não decidiu explicitamente.

## Proposta
- **Modelo de conta** (saldo + nonce por endereço), não UTXO: mais simples para contratos, bens e credenciais.
- **Endereço** `brdc1…` em **bech32m** (checksum robusto, detecta erro de digitação), derivado da chave pública Ed25519 por hash etiquetado.
- **6 casas decimais** (como o USDC): unidade mínima 0,000001 BRDC; valores internos sempre inteiros (nunca ponto flutuante).

## Alternativas
UTXO (bom para privacidade e paralelismo, ruim para estado de contratos); 2 casas (centavos, sem folga para taxas pequenas); 18 casas (excesso para uma moeda em reais).

## Consequências
Os testes da Fase 1 e 2 assumem esta proposta; mudar depois custa caro, por isso a confirmação vem antes do código.
