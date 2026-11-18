defmodule BrdcDev.EquivocationTest do
  # um validador (o 4) vira bizantino: assina dois votos conflitantes; os 3 honestos têm de DETECTAR e a rede seguir
  use ExUnit.Case, async: false
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcDev.Equivocation
  alias BrdcLedger.Tx
  alias BrdcNode.{Client, Genesis, Keygen, Validator}

  @moduletag :tmp_dir
  @moduletag timeout: 180_000
  @chain "equivocation-test"

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

  # só os 3 honestos sobem; o 4º é quem equivoca
  defp start_honest(dir, path, keys, ports) do
    for i <- 1..3 do
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

  defp endpoint(v), do: {~c"127.0.0.1", v.client_port}

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

  test "os honestos DETECTAM o voto duplo e a rede continua viva (3 de 4 mantêm o quórum)", %{
    tmp_dir: dir
  } do
    {keys, ports, path} = setup_files(dir)
    honest = start_honest(dir, path, keys, ports)
    endpoints = Enum.map(honest, &endpoint/1)

    assert {:ok, r} =
             Equivocation.run(
               genesis: path,
               seed: keys["v4"].seed_path,
               endpoints: endpoints,
               peer_port: ports[4],
               duration_ms: 20_000,
               connect_ms: 20_000
             )

    assert r.equivocator == Address.from_public_key(keys["v4"].public_key)
    assert r.honest == 3
    assert r.detected == 3, "todos os honestos deviam ter detectado: #{inspect(r.evidence)}"
    assert r.passed
    assert Enum.all?(r.evidence, &(&1.after > &1.before))

    # vivacidade: depois do voto duplo, uma transação ainda vira bloco nos 3 honestos, com o mesmo hash
    to = Address.hash(keys["i1"].public_key)

    assert {:ok, _} =
             Client.submit_tx(hd(endpoints), mint(keys, to, 1_000_000, "pos-equivocacao"))

    assert :ok =
             await(
               fn ->
                 Enum.all?(endpoints, fn ep ->
                   match?({:ok, %{height: h}} when h >= 1, Client.status(ep))
                 end)
               end,
               30_000
             )

    hashes = for ep <- endpoints, do: elem(Client.status(ep), 1).last_hash
    assert hashes |> Enum.uniq() |> length() == 1
  end

  test "uma chave que não é de validador não pode equivocar (e sem pares a execução falha clara)",
       %{tmp_dir: dir} do
    {keys, ports, path} = setup_files(dir)
    {:ok, intruder} = Keygen.generate(dir, "intruso")

    assert {:error, :not_a_validator} =
             Equivocation.run(
               genesis: path,
               seed: intruder.seed_path,
               endpoints: [],
               peer_port: 0
             )

    # nenhum honesto no ar: não conecta a ninguém (e não confunde "não li" com "zero evidências")
    assert {:error, :no_peers} =
             Equivocation.run(
               genesis: path,
               seed: keys["v4"].seed_path,
               endpoints: [{~c"127.0.0.1", 9}],
               peer_port: ports[4],
               connect_ms: 500
             )
  end

  test "se não dá para LER a evidência de um honesto, falha cedo (nunca confunde 'não li' com 'zero')",
       %{tmp_dir: dir} do
    {keys, ports, path} = setup_files(dir)
    honest = start_honest(dir, path, keys, ports)

    # um nó sem consenso (solo): responde "sem consenso" à consulta
    {:ok, g} =
      Genesis.new(
        chain_id: "solo",
        validators: [keys["v1"].public_key],
        issuers: [keys["i1"].public_key],
        threshold: 1
      )

    {:ok, solo} =
      BrdcNode.Node.start_link(
        genesis: g,
        seed: elem(Keygen.load_seed(keys["v1"].seed_path), 1),
        block_interval_ms: :manual
      )

    {:ok, guard} = BrdcP2p.Guard.start_link(sweep_ms: :never)

    {:ok, pp} =
      BrdcP2p.PublicPort.start_link(guard: guard, handler: BrdcNode.Handler.fun(solo), port: 0)

    on_exit(fn -> catch_exit(BrdcP2p.PublicPort.stop(pp)) end)
    blind = {~c"127.0.0.1", BrdcP2p.PublicPort.port(pp)}

    assert {:error, {:consensus_unavailable, [^blind]}} =
             Equivocation.run(
               genesis: path,
               seed: keys["v4"].seed_path,
               endpoints: Enum.map(honest, &endpoint/1) ++ [blind],
               peer_port: ports[4],
               duration_ms: 2_000
             )
  end
end
