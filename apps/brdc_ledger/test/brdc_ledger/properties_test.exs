defmodule BrdcLedger.PropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcLedger.{Block, Executor, Params, State, Tx}

  @chain "brdc-prop"
  defp seed(n), do: :crypto.hash(:sha256, "prop-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))
  defp addr(n), do: Address.hash(pub(n))

  defp base do
    {:ok, p} = Params.new(chain_id: @chain, issuers: [pub(101), pub(102)], threshold: 2)
    State.new(p)
  end

  defp signed(kind, n, nonce, fee, payload) do
    %Tx{
      chain_id: @chain,
      kind: kind,
      nonce: nonce,
      fee: fee,
      sender_pub: Account.from_seed(seed(n)).public_key,
      payload: payload
    }
    |> Tx.sign(seed(n))
  end

  defp op_gen do
    one_of([
      tuple({constant(:mint), integer(1..5), integer(1..1_000_000)}),
      tuple({constant(:burn), integer(1..5), integer(1..1_000_000)}),
      tuple({constant(:transfer), integer(1..5), integer(1..5), integer(1..1_000_000)})
    ])
  end

  # Executa uma lista de operações, ignorando as recusadas, e confere os invariantes a cada passo.
  defp run(ops) do
    ops
    |> Enum.with_index()
    |> Enum.reduce(base(), fn {op, i}, s ->
      tx = to_tx(s, op, i)

      case Executor.apply_tx(s, tx) do
        {:ok, s2, fee} ->
          # a taxa fica "no ar" até o bloco repartir; devolvemos ao primeiro validador para fechar a conta
          s3 =
            State.put_account(s2, addr(200), %{
              balance: State.balance(s2, addr(200)) + fee,
              nonce: 0
            })

          assert State.total_balances(s3) == State.supply(s3)
          s3

        {:error, _} ->
          s
      end
    end)
  end

  defp to_tx(s, {:mint, n, amt}, i) do
    doc = Tx.issuance_doc(:mint, @chain, addr(n), amt, "r#{i}")
    ap = for k <- [101, 102], do: Tx.approval(doc, seed(k))

    signed(
      2,
      9,
      State.account(s, addr(9)).nonce,
      0,
      Tx.issuance_payload(addr(n), amt, "r#{i}", ap)
    )
  end

  defp to_tx(s, {:burn, n, amt}, i) do
    doc = Tx.issuance_doc(:burn, @chain, addr(n), amt, "b#{i}")
    ap = for k <- [101, 102], do: Tx.approval(doc, seed(k))

    signed(
      3,
      n,
      State.account(s, addr(n)).nonce,
      0,
      Tx.issuance_payload(addr(n), amt, "b#{i}", ap)
    )
  end

  defp to_tx(s, {:transfer, a, b, amt}, _i) do
    t = signed(1, a, State.account(s, addr(a)).nonce, 0, Tx.transfer_payload(addr(b), amt))
    signed(1, a, t.nonce, Executor.min_fee(s.params, t), t.payload)
  end

  property "oferta = emitido − queimado = soma dos saldos, em qualquer sequência de operações" do
    check all(ops <- list_of(op_gen(), max_length: 40), max_runs: 60) do
      s = run(ops)
      assert State.supply(s) == s.minted - s.burned
      assert State.total_balances(s) == State.supply(s)
    end
  end

  property "o mesmo bloco sobre o mesmo estado dá a mesma raiz (determinismo)" do
    check all(amt <- integer(1..1_000_000), max_runs: 30) do
      doc = Tx.issuance_doc(:mint, @chain, addr(1), amt, "x")
      ap = for k <- [101, 102], do: Tx.approval(doc, seed(k))
      t = signed(2, 9, 0, 0, Tx.issuance_payload(addr(1), amt, "x", ap))
      {:ok, b1, s1} = Block.build(base(), addr(50), [addr(50)], [t])
      {:ok, s2} = Block.apply(base(), b1)
      assert State.root(s1) == State.root(s2)
    end
  end

  property "decodificar lixo nunca levanta exceção" do
    check all(bin <- binary()) do
      assert match?({:ok, _}, Tx.decode(bin)) or Tx.decode(bin) == {:error, :malformed}
    end
  end
end
