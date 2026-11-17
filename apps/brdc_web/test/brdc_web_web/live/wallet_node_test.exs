defmodule BrdcWebWeb.WalletNodeTest do
  @moduledoc "A carteira (servidor) como cliente de um nó de verdade, pela porta pública em TCP."
  use BrdcWebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcLedger.{Contracts, Tx}
  alias BrdcNode.{Genesis, Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @abandon "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
  defp seed(n), do: :crypto.hash(:sha256, "web-node-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))

  setup do
    {:ok, g} =
      Genesis.new(
        chain_id: "web-test",
        validators: [pub(1)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        min_window: 1
      )

    {:ok, node} = Node.start_link(genesis: g, seed: seed(1), block_interval_ms: :manual)
    {:ok, guard} = Guard.start_link(sweep_ms: :never)
    {:ok, port_pid} = PublicPort.start_link(guard: guard, handler: Handler.fun(node), port: 0)

    Application.put_env(:brdc_web, :node, host: ~c"127.0.0.1", port: PublicPort.port(port_pid))

    on_exit(fn ->
      Application.delete_env(:brdc_web, :node)

      try do
        PublicPort.stop(port_pid)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, node: node}
  end

  defp alice, do: elem(Account.from_mnemonic(@abandon), 1)
  defp bob, do: elem(Account.from_mnemonic(@abandon, "segredo"), 1)

  defp fund(node, account, amount, ref) do
    hash = Address.hash(account.public_key)
    d = Tx.issuance_doc(:mint, "web-test", hash, amount, ref)
    ap = for i <- [10, 11], do: Tx.approval(d, seed(i))
    nonce = Node.account(node, Address.hash(pub(10)), pending: true).nonce

    tx =
      %Tx{
        chain_id: "web-test",
        kind: 2,
        nonce: nonce,
        fee: 0,
        sender_pub: pub(10),
        payload: Tx.issuance_payload(hash, amount, ref, ap)
      }
      |> Tx.sign(seed(10))

    {:ok, _} = Node.submit(node, Tx.encode(tx))
    {:ok, _} = Node.produce(node) |> then(&{:ok, &1})
  end

  defp transfer_hex(node, from, to, amount) do
    %{nonce: nonce} = Node.account(node, Address.hash(from.public_key), pending: true)
    {:ok, to_hash} = Address.decode(to.address)

    t = %Tx{
      chain_id: "web-test",
      kind: 1,
      nonce: nonce,
      fee: 0,
      sender_pub: from.public_key,
      payload: Tx.transfer_payload(to_hash, amount)
    }

    fee = 1_000 + (byte_size(Tx.signing_bytes(t)) + 64)
    Base.encode16(Tx.encode(Tx.sign(%{t | fee: fee}, from.seed)), case: :lower)
  end

  test "destravada com saldo: mostra o saldo real e a rede", %{conn: conn, node: node} do
    fund(node, alice(), 12_500_000, "a")
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})
    html = render(view)
    assert html =~ "12"
    assert html =~ "50"
    assert html =~ "web-test"
    assert html =~ "bloco 1"
    refute html =~ "Sem conexão"
  end

  test "sem nó configurado: a carteira funciona e avisa que está sem conexão", %{conn: conn} do
    Application.delete_env(:brdc_web, :node)
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})
    html = render(view)
    assert html =~ "Seu endereço"
    assert html =~ "Sem conexão com a rede"
  end

  test "wallet:prepare devolve só dados públicos, com os números como texto", %{
    conn: conn,
    node: node
  } do
    fund(node, alice(), 5_000_000, "a")
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})

    render_hook(view, "wallet:prepare", %{})

    assert_reply(view, %{
      ok: true,
      chain_id: "web-test",
      nonce: "0",
      balance: "5000000",
      transfer_base: "1000",
      per_byte: "1",
      contract_fee: "10000"
    })
  end

  test "wallet:submit responde com o id; recusas respondem com o motivo", %{
    conn: conn,
    node: node
  } do
    fund(node, alice(), 5_000_000, "a")
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})

    hex = transfer_hex(node, alice(), bob(), 1_000)
    render_hook(view, "wallet:submit", %{"tx" => hex})
    assert_reply(view, %{ok: true, id: id})
    assert byte_size(id) == 64

    render_hook(view, "wallet:submit", %{"tx" => hex})
    assert_reply(view, %{ok: false, error: "duplicate"})
    render_hook(view, "wallet:submit", %{"tx" => "zz"})
    assert_reply(view, %{ok: false, error: "malformed"})
    render_hook(view, "wallet:submit", %{"tx" => transfer_hex(node, alice(), bob(), 900_000_000)})
    assert_reply(view, %{ok: false, error: "insufficient_funds"})
    render_hook(view, "wallet:submit", %{"tx" => transfer_hex(node, bob(), alice(), 1)})
    assert_reply(view, %{ok: false, error: "not_your_address"})
  end

  test "enviar: a transação assinada no cliente chega ao nó e o saldo muda depois do bloco", %{
    conn: conn,
    node: node
  } do
    fund(node, alice(), 5_000_000, "a")
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})

    hex = transfer_hex(node, alice(), bob(), 1_000_000)
    render_hook(view, "wallet:submit", %{"tx" => hex})

    assert Node.status(node).pending == 1
    assert {:ok, 2} = Node.produce(node)
    assert Node.account(node, Address.hash(bob().public_key)).balance == 1_000_000

    send(view.pid, :refresh)
    html = render(view)
    assert html =~ "bloco 2"
    assert html =~ "3"
  end

  test "recusas: tx de outro endereço, hex inválido, sem fundos", %{conn: conn, node: node} do
    fund(node, alice(), 2_000_000, "a")
    fund(node, bob(), 2_000_000, "b")
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})

    # transação assinada pelo Bob, enviada pela carteira da Alice
    render_hook(view, "wallet:submit", %{"tx" => transfer_hex(node, bob(), alice(), 1_000)})
    # hex inválido e lixo
    render_hook(view, "wallet:submit", %{"tx" => "zz"})
    render_hook(view, "wallet:submit", %{"tx" => "abcd"})
    # sem fundos
    render_hook(view, "wallet:submit", %{"tx" => transfer_hex(node, alice(), bob(), 900_000_000)})

    assert Node.status(node).pending == 0
  end

  test "nada de segredo no servidor: o evento de envio só carrega a transação", %{
    conn: conn,
    node: node
  } do
    fund(node, alice(), 5_000_000, "a")
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})
    hex = transfer_hex(node, alice(), bob(), 1_000)

    html =
      render_hook(view, "wallet:submit", %{
        "tx" => hex,
        "mnemonic" => @abandon,
        "password" => "uma senha qualquer 123"
      })

    refute html =~ "abandon abandon"
    refute html =~ "uma senha qualquer"
  end

  test "contratos do endereço chegam ao navegador (endereços brdc1…, números como texto) e atualizam",
       %{conn: conn, node: node} do
    fund(node, alice(), 5_000_000, "a")
    fund(node, bob(), 5_000_000, "b")
    {:ok, bob_hash} = Address.decode(bob().address)

    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => alice().address})
    # sem contratos ainda: lista vazia
    assert_push_event(view, "contracts", %{contracts: [], address: _, time: _})

    # Alice cria uma compra e venda com o Bob
    %{nonce: nonce} = Node.account(node, Address.hash(alice().public_key), pending: true)
    payload = Contracts.create_payload("compra-venda", "cv-1", bob_hash, [1_000_000, 100])

    tx = %Tx{
      chain_id: "web-test",
      kind: 20,
      nonce: nonce,
      fee: 10_000,
      sender_pub: alice().public_key,
      payload: payload
    }

    {:ok, _} = Node.submit(node, Tx.encode(Tx.sign(tx, alice().seed)))
    {:ok, _} = Node.produce(node) |> then(&{:ok, &1})

    send(view.pid, :refresh)

    assert_push_event(view, "contracts", %{
      address: addr,
      contracts: [
        %{
          id: "cv-1",
          template: "compra-venda",
          state: "open",
          escrow: "0",
          a: a,
          b: b,
          terms: terms
        }
      ]
    })

    assert addr == alice().address
    assert a == alice().address and b == bob().address
    assert terms == %{"price" => "1000000", "duration" => "100"}
  end
end
