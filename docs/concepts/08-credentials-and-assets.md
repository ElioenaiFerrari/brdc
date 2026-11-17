# 8. Credenciais e bens

## Credenciais
Uma **credencial** é uma afirmação sobre um titular emitida por um **órgão** (CNH, identificação, certidão de casamento, certidão de divórcio…). Na BRDC:

- Cada **tipo** de credencial tem um **órgão** formado por **M-de-N membros**: a emissão exige M aprovações.
- Há uma **janela de contestação** depois da aprovação: o órgão pode **vetar**. Passada a janela, a credencial fica **ativa**, até a **validade** (ou para sempre) ou até ser **revogada**.
- **Pública:** os dados ficam em claro na chain (por exemplo, uma candidatura). **Privada:** a chain guarda só um **compromisso** (um hash dos dados com um sal) e os dados ficam com o titular, que escolhe o que revelar. CNH, identificação e certidões são **privadas**.

### Casamento e divórcio
- O casamento gera **uma credencial por cônjuge**, com a mesma matrícula e cada uma nomeando o outro.
- O divórcio gera uma credencial para cada ex-cônjuge, referencia a matrícula do casamento e **revoga** as certidões de casamento: o casamento deixa de valer e o divórcio fica como prova.
- A chain **não valida** os dados privados (só o compromisso): a coerência é garantida por quem emite e por quem verifica o que o titular mostra.

## Bens e propriedade
Um **bem** (imóvel, veículo…) pertence a uma **classe** com seu **órgão** (cartório, Detran). O órgão **registra** o bem (com um hash dos metadados, que ficam fora da chain). A **transferência** funciona como negociação direta com **escrow**:

1. o dono faz uma **oferta** (bem e preço em BRDC);
2. o comprador **aceita**, e o preço fica travado em escrow;
3. abre-se a **janela de veto** do órgão;
4. sem veto, a **finalização** passa o bem ao comprador e o preço ao vendedor; com veto, o preço volta ao comprador.
Há também **gravames** (ônus) que impedem a transferência enquanto existirem.

## Como a BRDC usa
Credenciais e bens são **módulos nativos** do ledger ([ADR-0004](../adr/0004-native-contracts-and-declarative-templates.md)); o pagamento usa a própria BRDC em escrow. As janelas (contestação e veto) são decisões **pendentes** (P4).

## Onde está no código
*Planejado (Fase 5, módulos `credentials` e `assets` em `brdc_ledger`). O projeto irmão Teko tem as versões em Rust (`teko-credentials`, `teko-assets`).*

## Limites honestos
Sem validade jurídica; um órgão desonesto (M-de-N em conluio) pode emitir ou vetar o que quiser: a confiança está nos órgãos, não na matemática.
