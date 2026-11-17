# ADR-0004 — Contratos nativos e modelos declarativos

**Status:** Aceito (dono do produto, 2026-11-17)

## Contexto
Precisamos de "contratos inteligentes" para propriedade, credenciais e acordos entre partes. Opções: **módulos nativos + modelos declarativos**; **máquina virtual própria ou WASM**; **EVM (Solidity)**.

## Decisão
Os tipos de contrato são **módulos Elixir revisados e determinísticos** (moeda, reservas, bens, credenciais, governança). Contratos **entre partes** são instanciados por **modelos declarativos** (máquinas de estado: partes, condições, prazos, assinaturas, valores em BRDC e escrow). **Não há VM**, nem execução de código arbitrário de terceiros.

## Alternativas descartadas
VM/WASM (projeto enorme: determinismo, medição de gás, sandbox e uma classe de bugs de segurança); EVM (sem implementação madura em Elixir e baixa aderência a credenciais e bens brasileiros).

## Consequências
- **Segurança e auditabilidade:** o conjunto de comportamentos possíveis é pequeno e revisável.
- **Menos flexibilidade:** um contrato novo exige um modelo novo ou um módulo novo, passando por revisão e atualização da rede (rotação de versão do protocolo).
- Todo módulo segue um contrato de comportamento (`behaviour`) comum de validação e execução, puro e determinístico.
