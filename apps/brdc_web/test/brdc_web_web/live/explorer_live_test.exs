defmodule BrdcWebWeb.ExplorerLiveTest do
  @moduledoc "O explorador público lendo um nó de verdade pela porta pública: só leitura, certificado conferido."
  use BrdcWebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias BrdcConsensus.{Certificate, Vote}
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcLedger.{Block, Tx}
  alias BrdcNode.{Genesis, Handler, Node}
  alias BrdcP2p.{Guard, PublicPort}

  @abandon "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
  defp seed(n), do: :crypto.hash(:sha256, "explorer-web-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))

  setup do
    {:ok, g} =
      Genesis.new(
        chain_id: "explorer-web",
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
      catch_exit(PublicPort.stop(port_pid))
    end)

    {:ok, node: node}
  end

  defp alice, do: elem(Account.from_mnemonic(@abandon), 1)

  # emite `amount` para a conta e produz o bloco; devolve o id (hex) da transação
  defp fund(node, account, amount, ref) do
    hash = Address.hash(account.public_key)
    d = Tx.issuance_doc(:mint, "explorer-web", hash, amount, ref)
    ap = for i <- [10, 11], do: Tx.approval(d, seed(i))
    nonce = Node.account(node, Address.hash(pub(10)), pending: true).nonce

    tx =
      Tx.sign(
        %Tx{
          chain_id: "explorer-web",
          kind: 2,
          nonce: nonce,
          fee: 0,
          sender_pub: pub(10),
          payload: Tx.issuance_payload(hash, amount, ref, ap)
        },
        seed(10)
      )

    {:ok, _} = Node.submit(node, Tx.encode(tx))
    commit_with_cert(node)
    Base.encode16(Tx.id(tx), case: :lower)
  end

  # como a rede faz: propõe, o validador assina o precommit, o nó confirma com o certificado
  defp commit_with_cert(node) do
    {:ok, block} = Node.build_proposal(node)

    vote =
      Vote.sign("explorer-web", :precommit, block.height, 0, Block.hash(block), seed(1))

    cert = %Certificate{
      height: block.height,
      round: 0,
      block_hash: Block.hash(block),
      votes: [vote]
    }

    {:ok, _} = Node.commit_block(node, block, cert)
  end

  test "sem nó configurado: mostra 'sem conexão' e a página continua de pé", %{conn: conn} do
    Application.delete_env(:brdc_web, :node)
    {:ok, _view, html} = live(conn, ~p"/explorer")
    assert html =~ "Sem conexão com a rede"
  end

  test "início: rede, blocos produzidos e validadores", %{conn: conn, node: node} do
    fund(node, alice(), 5_000_000, "r1")
    {:ok, _view, html} = live(conn, ~p"/explorer")
    assert html =~ "explorer-web"
    assert html =~ "Últimos blocos"
    assert html =~ "#1"
    assert html =~ "Em circulação 5,00 BRDC"
    assert html =~ "1 tx · 1 assin."
    assert html =~ "1 validador"
  end

  test "pendente aparece em 'Esperando bloco' e some depois de virar bloco", %{
    conn: conn,
    node: node
  } do
    {:ok, view, html} = live(conn, ~p"/explorer")
    assert html =~ "Nada pendente"

    hash = Address.hash(alice().public_key)
    d = Tx.issuance_doc(:mint, "explorer-web", hash, 1_000_000, "p1")
    ap = for i <- [10, 11], do: Tx.approval(d, seed(i))

    tx =
      Tx.sign(
        %Tx{
          chain_id: "explorer-web",
          kind: 2,
          nonce: 0,
          fee: 0,
          sender_pub: pub(10),
          payload: Tx.issuance_payload(hash, 1_000_000, "p1", ap)
        },
        seed(10)
      )

    {:ok, _} = Node.submit(node, Tx.encode(tx))
    send(view.pid, :tick)
    html = render(view)
    assert html =~ "Emissão (mint)"
    refute html =~ "Nada pendente"

    commit_with_cert(node)
    send(view.pid, :tick)
    assert render(view) =~ "Nada pendente"
  end

  test "bloco: certificado CONFERIDO, quem assinou e as transações", %{conn: conn, node: node} do
    fund(node, alice(), 5_000_000, "r1")
    {:ok, _view, html} = live(conn, ~p"/explorer/block/1")
    assert html =~ "Bloco 1"
    assert html =~ "Conferido"
    assert html =~ Address.from_public_key(pub(1))
    assert html =~ "Emissão (mint)"
    assert html =~ "5,00 BRDC"
  end

  test "nó solo (sem consenso) não tem certificado: o bloco aparece como NÃO conferido, com texto claro",
       %{conn: conn, node: node} do
    hash = Address.hash(alice().public_key)
    d = Tx.issuance_doc(:mint, "explorer-web", hash, 1_000_000, "solo")
    ap = for i <- [10, 11], do: Tx.approval(d, seed(i))

    tx =
      Tx.sign(
        %Tx{
          chain_id: "explorer-web",
          kind: 2,
          nonce: 0,
          fee: 0,
          sender_pub: pub(10),
          payload: Tx.issuance_payload(hash, 1_000_000, "solo", ap)
        },
        seed(10)
      )

    {:ok, _} = Node.submit(node, Tx.encode(tx))
    Node.produce(node)

    {:ok, _view, html} = live(conn, ~p"/explorer/block/1")
    assert html =~ "Não conferido"
    assert html =~ "rede de um nó só"
    refute html =~ ">Conferido<"
  end

  test "transação: valor, origem, destino e bloco, com ligações", %{conn: conn, node: node} do
    id = fund(node, alice(), 2_500_000, "r1")
    {:ok, _view, html} = live(conn, ~p"/explorer/tx/#{id}")
    assert html =~ "Emissão (mint)"
    assert html =~ "2,50"
    assert html =~ "Taxa"
    assert html =~ id
    assert html =~ alice().address
    assert html =~ ~s(href="/explorer/block/1")
  end

  test "conta: saldo e histórico", %{conn: conn, node: node} do
    fund(node, alice(), 3_000_000, "r1")
    {:ok, _view, html} = live(conn, ~p"/explorer/account/#{alice().address}")
    assert html =~ "3"
    assert html =~ "recebeu"
    assert html =~ "Emissão (mint)"
  end

  test "busca: altura, transação e endereço levam à página certa; texto solto dá aviso", %{
    conn: conn,
    node: node
  } do
    id = fund(node, alice(), 1_000_000, "r1")
    {:ok, view, _} = live(conn, ~p"/explorer")

    view |> form("form[role=search]", %{q: "1"}) |> render_submit()
    assert_patch(view, ~p"/explorer/block/1")

    view |> form("form[role=search]", %{q: id}) |> render_submit()
    assert_patch(view, ~p"/explorer/tx/#{id}")

    view |> form("form[role=search]", %{q: alice().address}) |> render_submit()
    assert_patch(view, ~p"/explorer/account/#{alice().address}")

    html = view |> form("form[role=search]", %{q: "oi"}) |> render_submit()
    assert html =~ "Digite uma altura"
  end

  test "bloco, transação e endereço que não existem ou estão malformados: aviso, sem erro", %{
    conn: conn
  } do
    {:ok, _v, html} = live(conn, ~p"/explorer/block/999")
    assert html =~ "não existe"
    {:ok, _v, html} = live(conn, ~p"/explorer/block/abc")
    assert html =~ "não existe"
    {:ok, _v, html} = live(conn, ~p"/explorer/tx/#{String.duplicate("0", 64)}")
    assert html =~ "Não achei essa transação"
    {:ok, _v, html} = live(conn, ~p"/explorer/tx/zzz")
    assert html =~ "Não achei essa transação"
    {:ok, _v, html} = live(conn, ~p"/explorer/account/brdc1errado")
    assert html =~ "Não achei"
  end

  test "somente leitura: sem cofre, sem ganchos de assinatura e com a CSP estrita", %{conn: conn} do
    conn = get(conn, ~p"/explorer")
    assert response(conn, 200) =~ "Explorador"
    assert [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "script-src 'self'"
    refute response(conn, 200) =~ "phx-hook"
    refute response(conn, 200) =~ "Assinar"
  end
end
