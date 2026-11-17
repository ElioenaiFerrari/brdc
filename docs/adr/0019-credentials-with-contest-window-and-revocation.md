# ADR-0019 — Credenciais: tipos com órgão, janela de contestação, validade e revogação

**Status:** Aceito (dono do produto, 2026-11-17: pedido original e "faça o que recomendou"; desenho do plano da Fase 5) · Usa [ADR-0016](0016-block-time-and-windows-in-seconds.md) (tempo) e [ADR-0018](0018-assets-direct-trade-with-veto-window.md) (autoridades raiz e órgãos).

## Contexto
Credenciais (CNH, identificação, certidão de casamento, certidão de divórcio…) são declarações de um **órgão** sobre uma pessoa. A chain não sabe se são verdadeiras: ela guarda **quem declarou o quê, quando, e se ainda vale**.

## Decisão
1. **Tipo de credencial:** criado pelas autoridades raiz (M-de-N). Fixa o **órgão** (chaves + limite M-de-N), a **janela de contestação** (segundos), a **validade** (segundos, `0` = não expira), a **privacidade** e, opcionalmente, uma **referência** a outro tipo.
2. **Privacidade:** **pública** (os dados, até 512 bytes, ficam na chain) ou **privada** (só um **compromisso** de 32 bytes, por exemplo o hash dos dados com um sal; o titular revela os dados fora da chain e qualquer um confere contra o compromisso).
3. **Emissão:** o órgão aprova (M-de-N) uma credencial com `cred_id` único, **titular** (endereço), dados ou compromisso e, se o tipo exige, a **referência** a outra credencial do mesmo titular. Ela nasce **pendente** e só vale depois da janela.
4. **Janela de contestação** (`prazo = horário do bloco + janela`): o **titular** pode **contestar** (recusa uma credencial errada) e o **órgão** pode **vetar** (M-de-N). Qualquer um **ativa** depois do prazo.
5. **Validade:** `expira em = horário da emissão + validade`. `State.credential_valid?/3` diz se uma credencial está ativa e não expirou.
6. **Revogação:** o órgão (M-de-N) revoga uma credencial pendente ou ativa. É definitiva.
7. **Casamento e divórcio:** duas credenciais **por cônjuge** (uma para cada), privadas e sem validade. O **divórcio** referencia o casamento do mesmo titular e, ao ser **ativado**, **revoga** esse casamento (tipo com `revoga a referência`).
8. **Sem reaproveitar:** o `cred_id` é único para sempre (mesmo contestada, vetada ou revogada, a entrada permanece com seu status), então uma aprovação nunca emite duas vezes.
9. **Taxas:** emitir e revogar **0,01 BRDC**; criar tipo **0,05 BRDC**; contestar, vetar e ativar sem taxa mínima.

## Consequências e limites honestos
- **O órgão é a fonte de verdade:** órgão comprometido emite credenciais falsas ou revoga as verdadeiras. A chain só prova a autoria.
- **Privada não é anônima:** o compromisso e o endereço do titular são públicos; só o conteúdo fica fora. Quem receber o conteúdo confere contra o compromisso.
- **Sem nome real na chain:** a ligação entre o endereço e a pessoa é feita pelo órgão fora da chain.
- A validade é **lida**, não executada: a credencial não "some" sozinha; quem a consulta confere o horário.
- Casamento e divórcio entre duas pessoas são duas credenciais independentes; a chain **não verifica** que as duas são do mesmo casal.
