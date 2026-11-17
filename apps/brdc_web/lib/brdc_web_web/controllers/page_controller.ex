defmodule BrdcWebWeb.PageController do
  use BrdcWebWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
