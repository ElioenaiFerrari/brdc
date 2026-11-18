defmodule BrdcNode.WireTest do
  use ExUnit.Case, async: true
  alias BrdcConsensus.{Certificate, Proposal, Vote}
  alias BrdcCrypto.{Address, Ed25519, Hash}
  alias BrdcLedger.Block
  alias BrdcNode.Wire

  defp seed(n), do: :crypto.hash(:sha256, "wire-#{n}")

  defp block(h \\ 1) do
    %Block{
      height: h,
      time: 1_000,
      prev_hash: if(h == 1, do: nil, else: :crypto.hash(:sha256, "prev")),
      proposer: Address.hash(Ed25519.public_key(seed(1))),
      signers: [Address.hash(Ed25519.public_key(seed(1)))],
      txs: [],
      state_root: :crypto.hash(:sha256, "root")
    }
  end

  defp cert(b) do
    h = Block.hash(b)
    votes = for n <- 1..3, do: Vote.sign("c", :precommit, b.height, 0, h, seed(n))
    %Certificate{height: b.height, round: 0, block_hash: h, votes: votes}
  end

  test "ida e volta de todas as mensagens" do
    b = block()
    p = Proposal.sign("c", 1, 0, -1, b, Hash.tagged("x", "y"), seed(1))
    v = Vote.sign("c", :prevote, 1, 0, nil, seed(2))

    msgs = [
      {:tx, "abc"},
      {:proposal, p},
      {:vote, v},
      {:status, 7, :crypto.hash(:sha256, "u")},
      {:status, 0, nil},
      {:get_blocks, 3, 16},
      {:blocks, [{b, cert(b)}, {block(2), cert(block(2))}]},
      {:blocks, []}
    ]

    for m <- msgs, do: assert({:ok, ^m} = Wire.decode(Wire.encode(m)))
  end

  test "recusa lixo, sobras, truncado, tipo desconhecido e vazio" do
    good = Wire.encode({:vote, Vote.sign("c", :prevote, 1, 0, nil, seed(2))})
    assert {:error, :malformed} = Wire.decode(<<>>)
    assert {:error, :malformed} = Wire.decode(<<99, 1, 2, 3>>)
    assert {:error, :malformed} = Wire.decode(good <> <<0>>)
    assert {:error, :malformed} = Wire.decode(binary_part(good, 0, byte_size(good) - 1))
    assert {:error, :malformed} = Wire.decode(<<3, "lixo">>)
    assert {:error, :malformed} = Wire.decode(<<2, "lixo">>)
    assert {:error, :malformed} = Wire.decode(<<6, "lixo">>)
  end

  test "limites: transação grande ou vazia, pedido de blocos zerado, grande demais ou da altura 0" do
    assert {:error, :malformed} = Wire.decode(<<1>>)
    assert {:ok, _} = Wire.decode(<<1, :binary.copy("x", 65_536)::binary>>)
    assert {:error, :malformed} = Wire.decode(<<1, :binary.copy("x", 65_537)::binary>>)
    assert {:error, :malformed} = Wire.decode(Wire.encode({:get_blocks, 1, 0}))
    assert {:error, :malformed} = Wire.decode(Wire.encode({:get_blocks, 1, 17}))
    assert {:error, :malformed} = Wire.decode(Wire.encode({:get_blocks, 0, 5}))
  end

  test "resposta com blocos demais é recusada; bloco sem certificado não é enviado" do
    b = block()
    many = for _ <- 1..17, do: {b, cert(b)}
    assert {:error, :malformed} = Wire.decode(Wire.encode({:blocks, many}))
    # no envio, entradas sem certificado são omitidas
    assert {:ok, {:blocks, [{^b, _}]}} =
             Wire.decode(Wire.encode({:blocks, [{b, cert(b)}, {block(2), nil}]}))
  end
end
