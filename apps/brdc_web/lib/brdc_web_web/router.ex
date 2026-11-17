defmodule BrdcWebWeb.Router do
  use BrdcWebWeb, :router

  # CSP estrita (ADR-0006/0020): só o próprio site, sem script nem estilo em linha, sem terceiros.
  @csp Enum.join(
         [
           "default-src 'self'",
           "script-src 'self'",
           "style-src 'self'",
           "img-src 'self' data:",
           "font-src 'self'",
           "connect-src 'self'",
           "object-src 'none'",
           "base-uri 'none'",
           "form-action 'self'",
           "frame-ancestors 'none'"
         ],
         "; "
       )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BrdcWebWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BrdcWebWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", BrdcWebWeb do
  #   pipe_through :api
  # end
end
