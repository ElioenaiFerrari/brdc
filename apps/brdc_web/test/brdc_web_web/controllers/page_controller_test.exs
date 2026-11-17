defmodule BrdcWebWeb.PageControllerTest do
  use BrdcWebWeb.ConnCase

  test "GET /design (pré-visualização)", %{conn: conn} do
    conn = get(conn, ~p"/design")
    body = html_response(conn, 200)
    assert body =~ "Saldo"
    assert body =~ "Assinaturas pendentes"

    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "script-src 'self'"
    refute csp =~ "unsafe-inline"
    refute csp =~ "unsafe-eval"
    refute body =~ "<script>"
  end
end
