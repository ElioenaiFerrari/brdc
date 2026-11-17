defmodule BrdcWebWeb.WalletLiveTest do
  use BrdcWebWeb.ConnCase
  import Phoenix.LiveViewTest
  alias BrdcCrypto.Account

  @abandon "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"

  defp address do
    {:ok, a} = Account.from_mnemonic(@abandon)
    a.address
  end

  test "a página traz o painel da carteira e nenhum campo ligado ao LiveView", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ ~s(phx-hook="Vault")
    assert html =~ "Criar carteira"
    assert html =~ "Já tenho uma frase"

    # nenhum campo sensível é enviado ao servidor: sem phx-change, phx-submit nem phx-blur nos campos
    for forbidden <- ["phx-change", "phx-submit", "phx-blur", "phx-keyup"] do
      refute html =~ forbidden, "o painel não pode usar #{forbidden}"
    end

    # nenhum campo tem atributo `name` (o navegador nem enviaria num envio de formulário comum)
    refute html =~ ~r/<(input|textarea)[^>]*\sname=/
    # senha e passphrase são campos protegidos
    assert html =~ ~s(type="password")
    # o painel é ignorado pelo LiveView (o JS manda nele)
    assert html =~ ~s(phx-update="ignore")
  end

  test "destravada: o servidor passa a mostrar o endereço (público) e só ele", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    refute html =~ "Seu endereço"

    html = render_hook(view, "wallet:unlocked", %{"address" => address()})
    assert html =~ "Seu endereço"
    assert html =~ address()
    assert html =~ "Bloquear"
  end

  test "bloqueada: o resumo some", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_hook(view, "wallet:unlocked", %{"address" => address()})
    html = render_hook(view, "wallet:locked", %{})
    refute html =~ "Seu endereço"
    refute html =~ address()
  end

  test "endereço inválido ou de outra rede é ignorado", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")

    for bad <- [
          "",
          "lixo",
          "btc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq",
          String.replace(address(), "brdc1", "brdc2")
        ] do
      html = render_hook(view, "wallet:unlocked", %{"address" => bad})
      refute html =~ "Seu endereço", "aceitou #{inspect(bad)}"
    end
  end

  test "parâmetros inesperados (inclusive frase ou senha) são ignorados e nunca aparecem na tela",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")

    html =
      render_hook(view, "wallet:unlocked", %{
        "address" => address(),
        "mnemonic" => @abandon,
        "password" => "uma senha bem longa 2026",
        "passphrase" => "segredo"
      })

    refute html =~ "abandon abandon"
    refute html =~ "uma senha bem longa"
    refute html =~ "segredo"
    # e eventos desconhecidos não derrubam a tela
    assert render_hook(view, "qualquer:coisa", %{"mnemonic" => @abandon}) =~ "Seu endereço"
    refute render_hook(view, "qualquer:coisa", %{"mnemonic" => @abandon}) =~ "abandon abandon"
  end

  test "a CSP continua estrita na carteira", %{conn: conn} do
    conn = get(conn, ~p"/")
    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "script-src 'self'"
    refute csp =~ "unsafe-inline"
    refute csp =~ "unsafe-eval"
    refute html_response(conn, 200) =~ "<script>"
  end
end
