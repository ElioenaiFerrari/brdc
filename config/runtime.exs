import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/brdc_web start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :brdc_web, BrdcWebWeb.Endpoint, server: true
end

config :brdc_web, BrdcWebWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Nó que a carteira e o explorador consultam (porta pública). Em dev o `dev.exs` já define o padrão; aqui vale
# para release (laboratório Docker, onde o nó é o serviço `v1`, por exemplo).
if port = System.get_env("BRDC_NODE_PORT") do
  config :brdc_web, :node,
    host: String.to_charlist(System.get_env("BRDC_NODE_HOST", "127.0.0.1")),
    port: String.to_integer(port)
end

# Papel deste processo no laboratório Docker (BRDC_ROLE): `validator` e `equivocator` leem a gênese e a semente de
# arquivos; `wallet` só sobe a web. Sem BRDC_ROLE nada muda (uso normal, `mix`).
case System.get_env("BRDC_ROLE") do
  nil ->
    :ok

  role when role in ["validator", "equivocator"] ->
    config :brdc_dev, :role,
      role: String.to_atom(role),
      genesis: System.get_env("BRDC_GENESIS", "/net/genesis.json"),
      seed: System.get_env("BRDC_SEED", "/run/seed"),
      data_dir: System.get_env("BRDC_DATA", "/data/chain"),
      peer_port: String.to_integer(System.get_env("BRDC_PEER_PORT", "4600")),
      public_port: String.to_integer(System.get_env("BRDC_PUBLIC_PORT", "4545")),
      interval_ms: String.to_integer(System.get_env("BRDC_INTERVAL_MS", "1000"))

  "wallet" ->
    config :brdc_dev, :role, role: :wallet

  other ->
    raise "BRDC_ROLE inválido: #{inspect(other)} (use validator, wallet ou equivocator)"
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :brdc_web, BrdcWebWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/brdc_web_web/router\.ex$"E,
        ~r"lib/brdc_web_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :brdc_web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :brdc_web, BrdcWebWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Origens aceitas no WebSocket do LiveView (sem isso, só a do `PHX_HOST`): vírgulas, ex.: //localhost:4100
  if origins = System.get_env("BRDC_ALLOWED_ORIGINS") do
    config :brdc_web, BrdcWebWeb.Endpoint, check_origin: String.split(origins, ",", trim: true)
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :brdc_web, BrdcWebWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :brdc_web, BrdcWebWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
