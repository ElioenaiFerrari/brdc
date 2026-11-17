# 6. Contratos nativos

## O que é um "contrato inteligente"
Um programa cujas regras são executadas pela própria rede, sem intermediário: "se o comprador pagar, a propriedade passa para ele". No Ethereum, qualquer pessoa publica código que roda numa **máquina virtual** (EVM). Isso é flexível, mas traz uma classe inteira de problemas: medição de gás, sandbox, bugs de reentrância, código imutável com falhas.

## A escolha da BRDC: módulos nativos + modelos declarativos
[ADR-0004](../adr/0004-native-contracts-and-declarative-templates.md): **não há VM**. Os tipos de contrato são **código Elixir revisado e determinístico**, parte do protocolo. São eles: moeda (`coin`), reservas e emissão (`reserve`), bens (`assets`), credenciais (`credentials`), governança (`governance`) e contratos entre partes (`contracts`).

Todo módulo segue um **contrato de comportamento** (`behaviour`) com duas funções puras:

```elixir
# ilustrativo (ainda não existe no código)
@callback validate(state, tx) :: :ok | {:error, reason}
@callback execute(state, tx) :: {:ok, new_state, events}
```

## Contratos entre partes: modelos declarativos
Um contrato entre pessoas (compra e venda, aluguel, empréstimo) é uma **máquina de estados** descrita por dados, não por código:

```elixir
# ilustrativo
%{
  template: "purchase_and_sale",
  parties: [:seller, :buyer],
  steps: [
    %{from: :proposed, on: {:sign, :buyer}, escrow: {:buyer, 100_000_000}, to: :funded},
    %{from: :funded,   on: {:sign, :seller}, release: {:escrow, :seller}, to: :done}
  ],
  deadline: ...
}
```
A rede só aceita as **transições do modelo**, valida assinaturas e prazos e **trava o dinheiro em escrow** (BRDC) até a condição. Para um comportamento novo, cria-se um modelo novo (ou um módulo), que passa por revisão e atualização do protocolo.

## Vantagens e custos
| | Módulos nativos + modelos | VM aberta |
|---|---|---|
| Segurança | conjunto pequeno de comportamentos, revisável | qualquer código, qualquer bug |
| Flexibilidade | limitada ao catálogo | total |
| Auditoria | fácil | difícil |
| Custo de um contrato novo | revisão + atualização do protocolo | publicar código |

## Onde está no código
*Planejado (Fases 2 e 5).*
