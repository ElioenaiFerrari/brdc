defmodule BrdcNode.ValidatorTest do
  # a rede montada SÓ por arquivos (chaves, gênese, sementes), como em dois computadores
  use ExUnit.Case, async: false
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.Tx
  alias BrdcNode.{Client, Genesis, Keygen, Validator}

  @moduletag :tmp_dir
  @moduletag timeout: 120_000
  @chain "validator-files"

  defp free_port do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)
    port
  end

  # chaves v1..v4 (validadores), i1 e i2 (emissores) e a gênese em arquivo, com os pares de partida
  defp setup_files(dir) do
    names = ~w(v1 v2 v3 v4 i1 i2)
    keys = Map.new(names, fn n -> {n, elem(Keygen.generate(dir, n), 1)} end)
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
    {g, keys, ports, path}
  end

  defp start_all(dir, path, keys, ports) do
    for i <- 1..4 do
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
  end

  defp await(fun, ms \\ 20_000) do
    deadline = System.monotonic_time(:millisecond) + ms
    do_await(fun, deadline)
  end

  defp do_await(fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("a condição não ficou verdadeira a tempo")

      true ->
        Process.sleep(50) && do_await(fun, deadline)
    end
  end

  defp endpoint(v), do: {~c"127.0.0.1", v.client_port}

  defp mint(keys, to, amount, ref) do
    {:ok, i1} = Keygen.load_seed(keys["i1"].seed_path)
    {:ok, i2} = Keygen.load_seed(keys["i2"].seed_path)
    {:ok, sender} = Keygen.load_seed(keys["v1"].seed_path)
    d = Tx.issuance_doc(:mint, @chain, to, amount, ref)

    %Tx{
      chain_id: @chain,
      kind: 2,
      nonce: 0,
      fee: 0,
      sender_pub: Ed25519.public_key(sender),
      payload: Tx.issuance_payload(to, amount, ref, [Tx.approval(d, i1), Tx.approval(d, i2)])
    }
    |> Tx.sign(sender)
    |> Tx.encode()
  end

  test "4 validadores subidos só por arquivos: a transação vira bloco em todos, com certificado conferido contra a gênese",
       %{tmp_dir: dir} do
    {g, keys, ports, path} = setup_files(dir)
    vs = start_all(dir, path, keys, ports)
    assert Enum.map(vs, & &1.index) == [1, 2, 3, 4]
    assert Enum.all?(vs, &(length(&1.peers) == 3))

    await(fn -> Enum.all?(vs, &(length(BrdcNode.Replica.connected(&1.replica)) == 3)) end)

    to = Address.hash(keys["i1"].public_key)
    assert {:ok, _} = Client.submit_tx(endpoint(Enum.at(vs, 1)), mint(keys, to, 3_000_000, "r1"))

    await(fn ->
      Enum.all?(vs, fn v -> match?({:ok, %{height: 1}}, Client.status(endpoint(v))) end)
    end)

    # cada validador entrega o mesmo bloco, e o certificado fecha contra as chaves FIXADAS da gênese
    hashes =
      for v <- vs do
        assert {:ok, r} = Client.block(endpoint(v), 1, g.validators)
        assert r.verified and r.trust == :pinned
        r.hash
      end

    assert hashes |> Enum.uniq() |> length() == 1
  end

  test "uma chave que não está na gênese não sobe como validador", %{tmp_dir: dir} do
    {_g, _keys, _ports, path} = setup_files(dir)
    {:ok, intruder} = Keygen.generate(dir, "intruso")

    assert {:error, :not_a_validator} =
             Validator.start(
               genesis: path,
               seed: intruder.seed_path,
               data_dir: Path.join(dir, "x")
             )
  end

  test "gênese ou semente ausentes, ou semente com permissão aberta, dão erro claro", %{
    tmp_dir: dir
  } do
    {_g, keys, _ports, path} = setup_files(dir)

    assert {:error, {:genesis, _, :enoent}} =
             Validator.start(
               genesis: Path.join(dir, "nao.json"),
               seed: keys["v1"].seed_path,
               data_dir: dir
             )

    assert {:error, :enoent} =
             Validator.start(genesis: path, seed: Path.join(dir, "nao.seed"), data_dir: dir)

    File.chmod!(keys["v1"].seed_path, 0o644)

    assert {:error, :insecure_permissions} =
             Validator.start(genesis: path, seed: keys["v1"].seed_path, data_dir: dir)
  end
end
