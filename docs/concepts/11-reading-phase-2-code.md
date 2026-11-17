# Como ler o código da Fase 2 (`brdc_ledger`)

Pré-requisito: [Blockchain e estado](01-blockchain-and-state.md) e [Stablecoin e emissores](05-stablecoin-and-issuers.md). Tudo em `apps/brdc_ledger/lib/brdc_ledger/`.

| # | Arquivo | O que faz |
|---|---|---|
| 1 | `params.ex` | parâmetros da gênese: `chain_id`, emissores, limite M-de-N, tabela de taxas (ADR-0014) |
| 2 | `tx.ex` | transação: campos, assinatura sobre **todos** os campos, id, codificação, cargas de transferência/mint/burn |
| 3 | `state.ex` | contas (saldo + nonce), emitido, queimado, referências usadas, **raiz de estado** |
| 4 | `executor.ex` | função pura `(estado, tx) → estado'` com todas as regras |
| 5 | `block.ex` | bloco atômico, repartição da taxa, hash do cabeçalho |

Valores em **unidades mínimas**: 1 BRDC = 1.000.000 ([ADR-0010](../adr/0010-account-model-address-and-decimals.md)). Fluxo com diagrama: [Fluxo 02](../flows/02-block-execution.md).

## Ideias-chave
- **Conta com nonce:** cada transação carrega o próximo número da conta; repetir uma transação falha (replay).
- **Assinatura cobre a rede:** o `chain_id` entra no que se assina, então uma transação não vale em outra rede.
- **Mint e burn:** não há "dono da moeda". Mint e burn exigem assinaturas de **M emissores** sobre um documento com conta, valor e **referência única** (ex.: o id do depósito). A mesma referência não emite duas vezes.
- **Burn só pelo dono:** o emissor atesta que pagou os reais, mas é o titular quem pede a destruição.
- **A taxa não some:** vai para quem assinou o bloco. Por isso, em qualquer momento, `soma dos saldos = emitido − queimado`.
- **Atestado de reserva:** M emissores assinam "a reserva é X" com número de sequência crescente. `State.coverage/1` mostra a margem (`{:covered, n}` ou `{:under, n}`). É informação para o público auditar; não bloqueia ninguém.
- **Sem halving:** não existe emissão automática ([ADR-0014](../adr/0014-fee-table-and-no-halving.md)).

## Rode você mesmo (`iex -S mix`)
```elixir
alias BrdcLedger.{Params, State, Tx, Executor}
seed = fn n -> :crypto.hash(:sha256, "demo-#{n}") end
pub = fn n -> BrdcCrypto.Ed25519.public_key(seed.(n)) end
addr = fn n -> BrdcCrypto.Address.hash(pub.(n)) end

{:ok, p} = Params.new(chain_id: "demo", issuers: [pub.(1), pub.(2)], threshold: 2)
s = State.new(p)

doc = Tx.issuance_doc(:mint, "demo", addr.(10), 5_000_000, "deposito-1")
ap = [Tx.approval(doc, seed.(1)), Tx.approval(doc, seed.(2))]
mint = %Tx{chain_id: "demo", kind: 2, nonce: 0, fee: 0, sender_pub: pub.(9),
           payload: Tx.issuance_payload(addr.(10), 5_000_000, "deposito-1", ap)} |> Tx.sign(seed.(9))

{:ok, s, _fee} = Executor.apply_tx(s, mint)
State.balance(s, addr.(10))   # => 5000000 (5 BRDC)
State.supply(s)               # => 5000000
```

## Limites honestos
Veja o [Fluxo 02](../flows/02-block-execution.md): o atestado é declaração dos emissores, a raiz de estado é uma Merkle simples (ADR-0012 proposto) e tudo fica em memória.
