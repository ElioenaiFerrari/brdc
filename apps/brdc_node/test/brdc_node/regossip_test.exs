defmodule BrdcNode.RegossipTest do
  # Uma transação enviada a um validador ANTES de os pares existirem (ou conectarem) tem de chegar a todos quando
  # eles conectam. A fofoca sai uma vez, para quem está conectado naquele instante; sem reenvio ao (re)conectar,
  # o proponente da rodada ficava sem a transação e segurava a rodada.
  use ExUnit.Case, async: false
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.Tx
  alias BrdcNode.{Client, Genesis, Keygen, Validator}

  @moduletag :tmp_dir
  @moduletag timeout: 120_000
  @chain "regossip-test"

  defp free_port do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)
    port
  end

  defp setup_files(dir) do
    keys = Map.new(~w(v1 v2 v3 v4 i1 i2), fn n -> {n, elem(Keygen.generate(dir, n), 1)} end)
    ports = Map.new(1..4, &{&1, free_port()})

    bootstrap =
      for i <- 1..4, do: %{validator: keys["v#{i}"].public_key, host: "127.0.0.1", port: ports[i]}

    {:ok, g} =
      Genesis.new(
        chain_id: @chain,
        validators: for(i <- 1..4, do: keys["v#{i}"].public_key),
        issuers: [keys["i1"].public_key, keys["i2"].public_key],
        threshold: 2,
        bootstrap: bootstrap,
        min_window: 1
      )

    path = Path.join(dir, "genesis.json")
    File.write!(path, Genesis.to_json(g))
    {keys, ports, path}
  end

  defp start(dir, path, keys, ports, i) do
    {:ok, v} =
      Validator.start(
        genesis: path,
        seed: keys["v#{i}"].seed_path,
        data_dir: Path.join(dir, "data-v#{i}"),
        peer_port: ports[i],
        public_port: 0,
        interval_ms: 50
      )

    v
  end

  defp endpoint(v), do: {~c"127.0.0.1", v.client_port}

  defp mint(keys, to) do
    {:ok, i1} = Keygen.load_seed(keys["i1"].seed_path)
    {:ok, i2} = Keygen.load_seed(keys["i2"].seed_path)
    {:ok, sender} = Keygen.load_seed(keys["v1"].seed_path)
    d = Tx.issuance_doc(:mint, @chain, to, 1_000_000, "regossip")

    %Tx{
      chain_id: @chain,
      kind: 2,
      nonce: 0,
      fee: 0,
      sender_pub: Ed25519.public_key(sender),
      payload:
        Tx.issuance_payload(to, 1_000_000, "regossip", [Tx.approval(d, i1), Tx.approval(d, i2)])
    }
    |> Tx.sign(sender)
  end

  # a transação já está em algum lugar do validador: no mempool ou (se já virou bloco) na cadeia
  defp has_tx?(v, id) do
    ep = endpoint(v)

    match?({:ok, _}, Client.tx(ep, id)) or
      (match?({:ok, list} when is_list(list), Client.mempool(ep)) and
         Enum.any?(elem(Client.mempool(ep), 1), &(&1.id == id)))
  end

  defp await(fun, ms) do
    deadline = System.monotonic_time(:millisecond) + ms

    Stream.repeatedly(fn ->
      cond do
        fun.() -> :ok
        System.monotonic_time(:millisecond) > deadline -> :timeout
        true -> Process.sleep(100) && :again
      end
    end)
    |> Enum.find(&(&1 != :again))
  end

  test "transação enviada a um validador sozinho chega aos demais LOGO que eles conectam", %{
    tmp_dir: dir
  } do
    {keys, ports, path} = setup_files(dir)

    # só o v3 está no ar (o proponente da altura 1, rodada 0, é o v2: o que recebe a transação NÃO é o proponente)
    sender = start(dir, path, keys, ports, 3)
    tx = mint(keys, Address.hash(keys["i1"].public_key))
    id = Tx.id(tx)
    assert {:ok, _} = Client.submit_tx(endpoint(sender), Tx.encode(tx))

    # os outros três sobem depois: ninguém estava conectado quando a transação foi espalhada
    others = for i <- [1, 2, 4], do: start(dir, path, keys, ports, i)
    all = [sender | others]

    assert :ok =
             await(
               fn ->
                 Enum.all?(
                   all,
                   &match?({:ok, %{connected: [_, _, _]}}, Client.consensus_info(endpoint(&1)))
                 )
               end,
               15_000
             )

    # O reenvio ao conectar leva a transação aos três em instantes. Sem ele, ela só chegaria com a proposta do
    # `v3`, depois de o prazo da rodada 0 vencer (2 s): bem depois desta janela.
    assert :ok = await(fn -> Enum.all?(others, &has_tx?(&1, id)) end, 1_200),
           "os pares não receberam a transação ao conectar"

    # e, claro, ela vira bloco em todos, com o mesmo hash
    assert :ok =
             await(
               fn ->
                 Enum.all?(all, &match?({:ok, %{height: 1}}, Client.status(endpoint(&1))))
               end,
               20_000
             )

    hashes = for v <- all, do: elem(Client.status(endpoint(v)), 1).last_hash
    assert hashes |> Enum.uniq() |> length() == 1
  end
end
