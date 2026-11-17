# ADR-0018 — Bens: classes com órgão, negociação direta e janela de veto

**Status:** Aceito (dono do produto, 2026-11-17: "faça o que recomendou"; desenho do plano da Fase 5) · Usa [ADR-0016](0016-block-time-and-windows-in-seconds.md) (tempo) e [ADR-0014](0014-fee-table-and-no-halving.md) (taxas).

## Contexto
A BRDC representa **bens** (imóveis, veículos…) e sua **transferência de propriedade** com pagamento em BRDC, sem juiz na chain. Quem garante que o bem existe e quem é o dono é um **órgão** (cartório, Detran…), não a chain.

## Decisão
1. **Autoridades raiz** (parâmetro da gênese: lista + limite M-de-N, distintas dos emissores e dos validadores) criam **classes** de bens. Cada classe fixa o **órgão** (lista de chaves + limite M-de-N) e a **janela de veto** (segundos, entre o mínimo e o máximo da gênese).
2. **Registro:** o órgão da classe aprova (M-de-N) o registro de um bem: `asset_id` único, dono inicial e metadado (até 256 bytes, normalmente um hash do documento).
3. **Negociação direta**, em etapas, cada uma uma transação:
   - **oferta** (só o dono, sem gravame e sem negociação em curso): comprador e preço;
   - **aceite** (só o comprador): o preço sai do saldo dele para o **escrow**, e a janela de veto começa (`prazo = horário do bloco + janela da classe`);
   - **veto** (aprovação M-de-N do órgão, só **antes** do prazo): o escrow volta ao comprador e a negociação acaba;
   - **finalização** (qualquer um, só **depois** do prazo): a propriedade passa ao comprador e o escrow vai ao vendedor;
   - **cancelamento** (só o dono, só antes do aceite).
4. **Gravames** (penhora, alienação fiduciária…): o órgão adiciona e remove, com M-de-N. Bem com gravame **não pode ser ofertado**, e uma negociação em janela **não finaliza** enquanto houver gravame.
5. **Aprovações do órgão não se repetem:** cada bem tem uma **revisão** (`rev`) que sobe a cada ação do órgão e entra no documento aprovado; a aprovação de veto também amarra comprador, preço e prazo.
6. **Taxas:** registrar bem ou criar classe **0,05 BRDC**; cada etapa da negociação **0,02 BRDC**; ações do órgão (veto, gravames) sem taxa mínima.
7. **Conservação:** o escrow é parte da oferta (`saldos + escrow = emitido − queimado`) e tem teste por propriedade.

## Consequências e limites honestos
- **A chain não sabe se o bem existe nem quem é o dono de verdade:** confia no órgão. Órgão comprometido (M assinaturas) pode registrar bens falsos ou vetar à vontade.
- **Sem arbitragem:** uma disputa é resolvida fora da chain; o órgão só tem o veto e os gravames.
- O comprador **fica com o dinheiro preso** durante a janela (24 h ou 48 h por padrão).
- O veto é só do órgão, não do vendedor nem do comprador, depois do aceite.
- Sem leilão, sem oferta a vários compradores e sem condições além do veto; podem entrar por ADR.
