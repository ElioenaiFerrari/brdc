defmodule BrdcP2p.Channel do
  @moduledoc """
  Canal entre validadores: TLS 1.3 mútuo com a chave de consenso fixada (ADR-0015).

  - Só `tlsv1.3`, `eddsa_ed25519`, `x25519`.
  - `verify_fun` confere, **no evento do certificado autoassinado**, que a chave pública está no
    conjunto de validadores **em vigor** (`validators` é uma função chamada a cada conexão, então
    a rotação vale sem reiniciar). Quem não está no conjunto é recusado no handshake.
  - Logo depois, o `hello` (`chain_id` + hash do genesis) é trocado; só então o par conta como
    autenticado (no TLS 1.3 o cliente pode concluir o `connect` antes de o servidor validar o
    certificado dele).
  - Toda leitura tem prazo e limite de tamanho.
  """
  alias BrdcCrypto.Encoding
  alias BrdcP2p.{Cert, Frame}

  @enforce_keys [:socket, :peer, :max_frame]
  defstruct [:socket, :peer, :max_frame]

  @type t :: %__MODULE__{socket: :ssl.sslsocket(), peer: <<_::256>>, max_frame: pos_integer()}
  @type config :: %{
          seed: <<_::256>>,
          chain_id: String.t(),
          genesis_hash: <<_::256>>,
          validators: (-> [<<_::256>>])
        }

  @hello [:string, {:fixed, 32}]
  @magic "brdc/p2p/1"

  # --- opções TLS -------------------------------------------------------------

  defp tls_opts(cfg) do
    cert = Cert.generate(cfg.seed)

    [
      versions: [:"tlsv1.3"],
      cert: cert.der,
      key: cert.key,
      cacerts: [cert.der],
      verify: :verify_peer,
      verify_fun: {&verify/3, cfg.validators},
      signature_algs: [:eddsa_ed25519],
      signature_algs_cert: [:eddsa_ed25519],
      supported_groups: [:x25519],
      active: false,
      mode: :binary
    ]
  end

  # Confiança = a chave pública do par está no conjunto de validadores em vigor.
  # A conferência tem de ficar AQUI: se este evento só fosse aceito, `valid_peer` nunca
  # dispararia e qualquer um entraria (armadilha comprovada, ADR-0015).
  defp verify(cert, {:bad_cert, reason}, validators)
       when reason in [:selfsigned_peer, :unknown_ca] do
    with {:ok, pub} <- Cert.public_key(cert), true <- pub in validators.() do
      {:valid, validators}
    else
      _ -> {:fail, :unknown_validator}
    end
  end

  defp verify(_cert, {:bad_cert, _} = e, _validators), do: {:fail, e}
  defp verify(_cert, {:extension, _}, validators), do: {:unknown, validators}
  defp verify(_cert, :valid, validators), do: {:valid, validators}

  defp verify(cert, :valid_peer, validators) do
    with {:ok, pub} <- Cert.public_key(cert), true <- pub in validators.() do
      {:valid, validators}
    else
      _ -> {:fail, :unknown_validator}
    end
  end

  # --- servidor -------------------------------------------------------------------

  @doc "Abre a porta de pares. `port: 0` escolhe uma livre (`port/1`)."
  @spec listen(config(), keyword()) :: {:ok, :ssl.sslsocket()} | {:error, term()}
  def listen(cfg, opts \\ []) do
    :ssl.listen(
      Keyword.get(opts, :port, 0),
      [reuseaddr: true, fail_if_no_peer_cert: true, backlog: 128] ++
        tls_opts(cfg) ++ Keyword.take(opts, [:ip])
    )
  end

  @doc "Porta em que o listener ficou."
  @spec port(:ssl.sslsocket()) :: non_neg_integer()
  def port(listener) do
    {:ok, {_, port}} = :ssl.sockname(listener)
    port
  end

  @doc "Aceita uma conexão: handshake com chave fixada e `hello`. Recusa quem não é do conjunto."
  @spec accept(:ssl.sslsocket(), config(), keyword()) :: {:ok, t()} | {:error, term()}
  def accept(listener, cfg, opts \\ []) do
    with {:ok, transport} <-
           accept_transport(listener, Keyword.get(opts, :accept_timeout, :infinity)) do
      upgrade(transport, cfg, opts)
    end
  end

  @doc "Aceita só a conexão TCP (o listener checa o IP antes do handshake)."
  @spec accept_transport(:ssl.sslsocket(), timeout()) ::
          {:ok, :ssl.sslsocket()} | {:error, term()}
  def accept_transport(listener, timeout), do: :ssl.transport_accept(listener, timeout)

  @doc "Faz o handshake TLS (chave fixada) e o `hello` numa conexão já aceita."
  @spec upgrade(:ssl.sslsocket(), config(), keyword()) :: {:ok, t()} | {:error, term()}
  def upgrade(transport, cfg, opts \\ []) do
    case :ssl.handshake(transport, Keyword.get(opts, :timeout, 5_000)) do
      {:ok, socket} -> finish(socket, cfg, opts)
      {:error, _} = err -> err
    end
  end

  # --- cliente --------------------------------------------------------------------

  @doc "Conecta a outro validador (handshake com chave fixada e `hello`)."
  @spec connect(charlist() | :inet.ip_address(), :inet.port_number(), config(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def connect(host, port, cfg, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, socket} <- :ssl.connect(host, port, tls_opts(cfg), timeout) do
      finish(socket, cfg, opts)
    end
  end

  # --- hello ------------------------------------------------------------------------

  defp finish(socket, cfg, opts) do
    max = Keyword.get(opts, :max_frame, Frame.default_max())
    timeout = Keyword.get(opts, :timeout, 5_000)

    with {:ok, der} <- :ssl.peercert(socket),
         {:ok, peer} <- peer_key(der),
         conn = %__MODULE__{socket: socket, peer: peer, max_frame: max},
         :ok <- send_frame(conn, hello(cfg)),
         {:ok, theirs} <- recv_frame(conn, timeout),
         :ok <- check_hello(theirs, cfg) do
      {:ok, conn}
    else
      {:error, _} = err ->
        :ssl.close(socket)
        err
    end
  end

  defp peer_key(der) do
    case Cert.public_key(der) do
      {:ok, pub} -> {:ok, pub}
      :error -> {:error, :bad_peer_cert}
    end
  end

  defp hello(cfg), do: Encoding.encode(@hello, [@magic <> "|" <> cfg.chain_id, cfg.genesis_hash])

  defp check_hello(bin, cfg) do
    case Encoding.decode(@hello, bin) do
      {:ok, [tag, genesis]} ->
        if tag == @magic <> "|" <> cfg.chain_id and genesis == cfg.genesis_hash,
          do: :ok,
          else: {:error, :wrong_network}

      _ ->
        {:error, :bad_hello}
    end
  end

  # --- quadros ------------------------------------------------------------------------

  @doc "Envia um quadro."
  @spec send_frame(t(), binary()) :: :ok | {:error, term()}
  def send_frame(%__MODULE__{socket: s, max_frame: max}, payload) do
    with {:ok, iodata} <- Frame.encode(payload, max), do: :ssl.send(s, iodata)
  end

  @doc "Lê um quadro, com prazo e limite de tamanho (conferido antes de ler o conteúdo)."
  @spec recv_frame(t(), timeout()) :: {:ok, binary()} | {:error, term()}
  def recv_frame(%__MODULE__{socket: s, max_frame: max}, timeout \\ 5_000) do
    with {:ok, header} <- :ssl.recv(s, 4, timeout),
         {:ok, n} <- Frame.parse_header(header, max) do
      if n == 0, do: {:ok, <<>>}, else: :ssl.recv(s, n, timeout)
    end
  end

  @doc "Fecha o canal."
  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: s}), do: :ssl.close(s)
end
