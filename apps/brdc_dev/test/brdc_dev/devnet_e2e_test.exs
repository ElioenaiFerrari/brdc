defmodule BrdcDev.DevnetE2ETest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcDev.{Devnet, Funding}
  alias BrdcLedger.{Contracts, Tx}
  alias BrdcNode.{Client, Genesis, Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @moduletag :tmp_dir
  @abandon "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

  defp boot(dir) do
    {:ok, devnet} = Devnet.ensure(dir)

    {:ok, node} =
      Node.start_link(
        genesis: devnet.genesis,
        seed: devnet.seeds["v1"],
        block_interval_ms: :manual
      )

    {:ok, guard} = Guard.start_link(sweep_ms: :never)
    {:ok, port_pid} = PublicPort.start_link(guard: guard, handler: Handler.fun(node), port: 0)
    on_exit(fn -> stop_quietly(port_pid) end)
    {devnet, node, {~c"127.0.0.1", PublicPort.port(port_pid)}}
  end

  defp stop_quietly(pid) do
    PublicPort.stop(pid)
  catch
    :exit, _ -> :ok
  end

  test "Devnet.ensure cria chaves 0600 e a gênese, e é idempotente (não troca as chaves)", %{
    tmp_dir: dir
  } do
    {:ok, a} = Devnet.ensure(dir)
    {:ok, b} = Devnet.ensure(dir)
    assert a.seeds == b.seeds
    assert Genesis.hash(a.genesis) == Genesis.hash(b.genesis)

    for role <- ~w(v1 i1 i2 a1 a2) do
      {:ok, stat} = File.stat(Path.join(dir, role <> ".seed"))
      assert Bitwise.band(stat.mode, 0o777) == 0o600
    end

    assert a.genesis.chain_id == "brdc-devnet"
    assert a.genesis.threshold == 2 and length(a.genesis.issuers) == 2
    assert a.genesis.contest_window == 60 and a.genesis.veto_window == 60
    assert length(a.genesis.authorities) == 2
  end

  test "outro diretório, outras chaves, outra gênese", %{tmp_dir: dir} do
    {:ok, a} = Devnet.ensure(Path.join(dir, "um"))
    {:ok, b} = Devnet.ensure(Path.join(dir, "dois"))
    refute Genesis.hash(a.genesis) == Genesis.hash(b.genesis)
  end

  test "pela rede de verdade: status, financiar, bloco, saldo", %{tmp_dir: dir} do
    {devnet, node, endpoint} = boot(dir)
    {:ok, acc} = Account.from_mnemonic(@abandon)
    {:ok, hash} = Address.decode(acc.address)

    assert {:ok, %{chain_id: "brdc-devnet", height: 0, pending: 0, transfer_base: 1_000}} =
             Client.status(endpoint)

    assert {:ok, %{balance: 0, nonce: 0}} = Client.account(endpoint, hash)

    assert {:ok, id} = Funding.mint(endpoint, devnet, hash, 12_500_000)
    assert byte_size(id) == 32
    # pendente: já aparece como pendente, ainda não como saldo
    assert {:ok, %{balance: 0, pending_balance: 12_500_000}} = Client.account(endpoint, hash)
    assert {:ok, %{pending: 1}} = Client.status(endpoint)

    assert {:ok, 1} = Node.produce(node)

    assert {:ok, %{balance: 12_500_000, pending_balance: 12_500_000}} =
             Client.account(endpoint, hash)

    assert {:ok, %{height: 1, supply: 12_500_000, pending: 0}} = Client.status(endpoint)

    # dois financiamentos seguidos usam nonces seguidos do emissor e não colidem
    assert {:ok, _} = Funding.mint(endpoint, devnet, hash, 2_500_000)
    assert {:ok, _} = Funding.mint(endpoint, devnet, hash, 1_000_000)
    assert {:ok, 2} = Node.produce(node)
    assert {:ok, %{balance: 16_000_000}} = Client.account(endpoint, hash)
  end

  test "transferência assinada pelo cliente chega pela rede, muda os saldos e paga a taxa ao validador",
       %{tmp_dir: dir} do
    {devnet, node, endpoint} = boot(dir)
    {:ok, alice} = Account.from_mnemonic(@abandon)
    {:ok, bob} = Account.from_mnemonic(@abandon, "segredo")
    {:ok, alice_hash} = Address.decode(alice.address)
    {:ok, bob_hash} = Address.decode(bob.address)

    {:ok, _} = Funding.mint(endpoint, devnet, alice_hash, 5_000_000)
    {:ok, 1} = Node.produce(node)

    {:ok, status} = Client.status(endpoint)
    {:ok, %{pending_nonce: nonce}} = Client.account(endpoint, alice_hash)

    payload = Tx.transfer_payload(bob_hash, 1_000_000)

    tx = %Tx{
      chain_id: status.chain_id,
      kind: 1,
      nonce: nonce,
      fee: 0,
      sender_pub: alice.public_key,
      payload: payload
    }

    fee = status.transfer_base + status.per_byte * (byte_size(Tx.signing_bytes(tx)) + 64)
    tx = Tx.sign(%{tx | fee: fee}, alice.seed)

    assert {:ok, id} = Client.submit_tx(endpoint, Tx.encode(tx))
    assert id == Tx.id(tx)
    {:ok, 2} = Node.produce(node)

    assert {:ok, %{balance: 1_000_000}} = Client.account(endpoint, bob_hash)
    assert {:ok, %{balance: remaining}} = Client.account(endpoint, alice_hash)
    assert remaining == 5_000_000 - 1_000_000 - fee

    validator_hash = Address.hash(Ed25519.public_key(devnet.seeds["v1"]))
    assert {:ok, %{balance: ^fee}} = Client.account(endpoint, validator_hash)
  end

  test "transação recusada volta como motivo pela rede e o nó segue de pé", %{tmp_dir: dir} do
    {_devnet, _node, endpoint} = boot(dir)
    assert {:error, :malformed} = Client.submit_tx(endpoint, "lixo")
    assert {:ok, %{pending: 0}} = Client.status(endpoint)
  end

  test "contratos entre partes pela rede: criar, aceitar, consultar por endereço", %{tmp_dir: dir} do
    {devnet, node, endpoint} = boot(dir)
    {:ok, alice} = Account.from_mnemonic(@abandon)
    {:ok, bob} = Account.from_mnemonic(@abandon, "segredo")
    {:ok, carol} = Account.from_mnemonic(@abandon, "carol")

    [a_hash, b_hash, c_hash] =
      for acc <- [alice, bob, carol], do: elem(Address.decode(acc.address), 1)

    {:ok, _} = Funding.mint(endpoint, devnet, a_hash, 5_000_000)
    {:ok, _} = Funding.mint(endpoint, devnet, b_hash, 5_000_000)
    {:ok, 1} = Node.produce(node)

    {:ok, status} = Client.status(endpoint)
    assert status.contract_fee == 10_000

    send_tx = fn acc, kind, payload ->
      {:ok, %{pending_nonce: nonce}} =
        Client.account(endpoint, elem(Address.decode(acc.address), 1))

      tx =
        %Tx{
          chain_id: status.chain_id,
          kind: kind,
          nonce: nonce,
          fee: status.contract_fee,
          sender_pub: acc.public_key,
          payload: payload
        }
        |> Tx.sign(acc.seed)

      Client.submit_tx(endpoint, Tx.encode(tx))
    end

    # Alice (vendedora) cria uma compra e venda com o Bob: preço 1 BRDC, prazo 100 s
    assert {:ok, _} =
             send_tx.(
               alice,
               20,
               Contracts.create_payload("compra-venda", "cv-1", b_hash, [1_000_000, 100])
             )

    assert {:ok, 2} = Node.produce(node)

    assert {:ok, [c]} = Client.contracts_of(endpoint, a_hash)

    assert %{
             id: "cv-1",
             template: "compra-venda",
             state: "open",
             escrow: 0,
             a: ^a_hash,
             b: ^b_hash
           } = c

    assert c.terms == %{"price" => 1_000_000, "duration" => 100}
    assert {:ok, [%{id: "cv-1"}]} = Client.contracts_of(endpoint, b_hash)
    assert {:ok, []} = Client.contracts_of(endpoint, c_hash)

    # Bob aceita: o preço vai para o escrow do contrato
    assert {:ok, _} = send_tx.(bob, 21, Contracts.act_payload("cv-1", "accept"))
    assert {:ok, 3} = Node.produce(node)
    assert {:ok, [funded]} = Client.contracts_of(endpoint, b_hash)
    assert %{state: "funded", escrow: 1_000_000} = funded
    assert Map.has_key?(funded.vars, "deadline")

    # quem não é parte não age; ação fora de hora é recusada pelo nó
    assert {:error, :not_party} = send_tx.(alice, 21, Contracts.act_payload("cv-1", "confirm"))
    assert {:error, :bad_state} = send_tx.(bob, 21, Contracts.act_payload("cv-1", "accept"))
  end

  test "consulta malformada volta como erro, sem derrubar o nó", %{tmp_dir: dir} do
    {_devnet, _node, {host, port}} = boot(dir)
    assert {:error, "bad_query"} = PublicPort.request(host, port, :query, <<9, 1, 2>>)
    assert {:error, "bad_query"} = PublicPort.request(host, port, :query, <<1, 1, 2>>)
    assert {:ok, _} = PublicPort.request(host, port, :status, <<>>)
  end
end
