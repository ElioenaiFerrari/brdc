# 2. Hash e assinatura

## Hash: a impressão digital de um dado
Uma **função hash** transforma qualquer dado em um número de tamanho fixo (32 bytes no SHA3-256) de modo que: o mesmo dado dá sempre o mesmo hash; mudar um bit muda o hash por inteiro; e é inviável achar outro dado com o mesmo hash. Usamos hashes para identificar transações, encadear blocos e resumir o estado.

**Roda hoje:**
```elixir
:crypto.hash(:sha3_256, "ola") |> Base.encode16(case: :lower)
# "f1cd78b728ae91867d7e982f39d3b4a1f84349085a19aeeefb189c8c104d241a"
```

### Hash etiquetado (separação de domínio)
Se o hash de uma transação pudesse ser confundido com o de um bloco, um atacante poderia reaproveitar uma assinatura onde não deveria. A solução é **prefixar o dado com uma etiqueta** única por uso:
```elixir
tagged = fn tag, data -> :crypto.hash(:sha3_256, [<<byte_size(tag)::32>>, tag, data]) end
tagged.("brdc/tx", "x") == tagged.("brdc/block", "x")   # => false
```
O tamanho da etiqueta entra no hash para que `("ab", "c")` e `("a", "bc")` também difiram. (Proposta no [ADR-0011](../adr/0011-deterministic-encoding-and-tagged-hash.md).)

## Assinatura digital
Um par de chaves: a **chave privada** (segredo, fica com o dono) e a **chave pública** (pode ser divulgada). Só quem tem a privada produz uma assinatura de uma mensagem; qualquer pessoa com a pública confere que ela é válida **e** que a mensagem não mudou. A BRDC usa **Ed25519**.

**Roda hoje:**
```elixir
{pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
sig = :crypto.sign(:eddsa, :none, "mensagem", [priv, :ed25519])
byte_size(pub)   # 32
byte_size(sig)   # 64
:crypto.verify(:eddsa, :none, "mensagem", sig, [pub, :ed25519])  # true
:crypto.verify(:eddsa, :none, "outra",    sig, [pub, :ed25519])  # false
```

## Como a BRDC usa
- A transação é assinada **no navegador** pela chave do usuário; o nó só verifica.
- A assinatura cobre o `chain_id` (para não valer em outra rede), o tipo, o **nonce** e todos os campos.
- O endereço `brdc1…` é derivado do hash etiquetado da chave pública.

## Erros comuns
- Assinar só parte da transação: o que não é assinado pode ser alterado por quem a repassa.
- Esquecer a separação de domínio.

## Onde está no código
*Planejado (Fase 1, `brdc_crypto`).*
