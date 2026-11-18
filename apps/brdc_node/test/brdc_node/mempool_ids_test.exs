defmodule BrdcNode.MempoolIdsTest do
  # A checagem de duplicata do mempool é O(1) (conjunto de ids), não "refazer o hash de todas as pendentes":
  # antes custava 0,5 ms com o mempool vazio e 15 ms com 7.500 pendentes, e saturava a CPU a partir de ~100 tx/s.
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.Tx
  alias BrdcNode.{Genesis, Node}

  @chain "mempool-ids"
  defp seed(n), do: :crypto.hash(:sha256, "mempool-ids-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))

  setup do
    {:ok, g} =
      Genesis.new(
        chain_id: @chain,
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        min_window: 1
      )

    {:ok, node} = Node.start_link(genesis: g, seed: seed(1), block_interval_ms: :manual)

    # um remetente (20) financiado por mint M-de-N e confirmado
    to = Address.hash(pub(20))
    d = Tx.issuance_doc(:mint, @chain, to, 1_000_000_000_000, "f")
    ap = for i <- [10, 11], do: Tx.approval(d, seed(i))

    mint =
      Tx.sign(
        %Tx{
          chain_id: @chain,
          kind: 2,
          nonce: 0,
          fee: 0,
          sender_pub: pub(10),
          payload: Tx.issuance_payload(to, 1_000_000_000_000, "f", ap)
        },
        seed(10)
      )

    {:ok, _} = Node.submit(node, Tx.encode(mint))
    {:ok, _} = Node.produce(node) |> then(&{:ok, &1})
    {:ok, node: node}
  end

  defp transfer(nonce) do
    Tx.sign(
      %Tx{
        chain_id: @chain,
        kind: 1,
        nonce: nonce,
        fee: 2_000,
        sender_pub: pub(20),
        payload: Tx.transfer_payload(:crypto.strong_rand_bytes(32), 1)
      },
      seed(20)
    )
    |> Tx.encode()
  end

  test "a mesma transação duas vezes: a segunda é :duplicate", %{node: node} do
    bin = transfer(0)
    assert {:ok, id} = Node.submit(node, bin)
    assert {:error, :duplicate} = Node.submit(node, bin)
    assert %{id: ^id} = hd(Node.explorer_mempool(node, 5))
  end

  test "depois de o bloco confirmar a transação, o id SAI do conjunto: reenviá-la não é 'duplicata fantasma'",
       %{node: node} do
    bin = transfer(0)
    {:ok, _} = Node.submit(node, bin)
    assert Node.status(node).pending == 1
    Node.produce(node)
    assert Node.status(node).pending == 0

    # agora o nonce 0 já foi usado: o erro é de nonce, NÃO :duplicate (o conjunto de ids foi refeito)
    assert {:error, reason} = Node.submit(node, bin)
    refute reason == :duplicate
  end

  test "o custo de enviar NÃO cresce com o tamanho do mempool (as últimas 1.000 não são muito mais lentas que as primeiras)",
       %{node: node} do
    bins = for n <- 0..2_999, do: transfer(n)

    time = fn chunk ->
      {us, _} = :timer.tc(fn -> for b <- chunk, do: {:ok, _} = Node.submit(node, b) end)
      us
    end

    [first, _, last] = Enum.chunk_every(bins, 1_000) |> Enum.map(time)
    # com o código antigo a razão era de ~5 a 10 vezes; agora fica perto de 1
    assert last < first * 3,
           "enviar ficou #{Float.round(last / first, 1)}x mais lento com o mempool cheio"
  end
end
