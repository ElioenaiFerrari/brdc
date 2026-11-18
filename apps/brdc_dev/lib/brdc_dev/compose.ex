defmodule BrdcDev.Compose do
  @moduledoc """
  Laboratório Docker (`docs/flows/22-docker-lab.md`): gera o `docker-compose.yml` de uma rede de teste com N
  validadores e M carteiras, **com recursos limitados** (CPU, memória e processos), e lê o estado dos validadores
  pelas portas que o Docker publica. A geração é uma **função pura** (`render/1`), testável sem Docker.

  Só desenvolvimento: a imagem inclui `brdc_dev` e chaves de teste.
  """
  alias BrdcDev.Devnet
  alias BrdcNode.Client

  @repo_root Path.expand("../../../..", __DIR__)
  @peer_port 4600
  @public_port 4545
  @web_port 4000

  @type opts :: %{
          validators: pos_integer(),
          wallets: non_neg_integer(),
          cpus: String.t(),
          memory: String.t(),
          wallet_memory: String.t(),
          base_port: pos_integer(),
          wallet_port: pos_integer(),
          interval_ms: pos_integer(),
          context: Path.t()
        }

  @doc "Pasta padrão do laboratório (`compose/` na raiz do repositório, ignorada pelo git)."
  @spec default_dir() :: Path.t()
  def default_dir, do: Path.join(@repo_root, "compose")

  @doc "Raiz do repositório (contexto da build da imagem)."
  @spec repo_root() :: Path.t()
  def repo_root, do: @repo_root

  @doc "Porta de pares dentro da rede do Docker (a mesma em todos os validadores)."
  @spec peer_port() :: pos_integer()
  def peer_port, do: @peer_port

  @doc "Porta publicada no computador para o validador `i`."
  @spec client_port(opts() | map(), pos_integer()) :: pos_integer()
  def client_port(%{base_port: base}, i), do: base + i - 1

  @doc """
  Padrões das opções (4 validadores e 2 carteiras; 3 CPUs e **2,0 GB** no máximo). Os 384 MiB do validador vêm do
  teste de carga: o pico de memória foi ~135 MiB a 50 tx/s, ~190 a 200, ~215 a 400 e ~290 a 800; com 192 MiB os
  validadores morriam por falta de memória (OOM, código 137) entre 100 e 200 tx/s.
  """
  @spec defaults() :: opts()
  def defaults do
    %{
      validators: 4,
      wallets: 2,
      cpus: "0.5",
      memory: "384m",
      wallet_memory: "256m",
      base_port: 4700,
      wallet_port: 4100,
      interval_ms: 1_000,
      context: @repo_root
    }
  end

  @doc "O texto do `docker-compose.yml`."
  @spec render(opts()) :: String.t()
  def render(o) do
    [header(o), services(o), "volumes:\n", volumes(o), "\nnetworks:\n  brdc: {}\n"]
    |> IO.iodata_to_binary()
  end

  defp header(o) do
    """
    # GERADO por `mix brdc.compose.init`: não edite (rode de novo). Laboratório de TESTE: chaves de teste na
    # pasta ao lado, imagem com `brdc_dev`. NÃO é produção.
    name: brdc-lab

    x-brdc: &brdc
      image: brdc-lab:dev
      build:
        context: #{o.context}
        dockerfile: Dockerfile
      init: true
      restart: unless-stopped
      pids_limit: 256
      cap_drop: [ALL]
      security_opt: ["no-new-privileges:true"]
      read_only: true
      tmpfs: ["/tmp"]
      env_file: .env
      networks: [brdc]

    x-env: &env
      # o BEAM enxerga todos os núcleos do computador: sem isto abriria um escalonador por núcleo dentro de 0,5 CPU
      ERL_AFLAGS: "+S 2:2 +A 8 +sbwt none +sbwtdcpu none +sbwtdio none"
      RELEASE_DISTRIBUTION: none
      RELEASE_TMP: /tmp
      ERL_CRASH_DUMP: /tmp/erl_crash.dump

    services:
    """
  end

  defp services(o) do
    validators = for i <- 1..o.validators, do: validator(o, i)
    wallets = for k <- 1..o.wallets//1, do: wallet(o, k)

    # o equivocador só existe com 4 ou mais validadores (o BFT só tolera um bizantino a partir de 4)
    byzantine = if o.validators >= 4, do: [equivocator(o)], else: []
    Enum.intersperse(validators ++ wallets ++ byzantine, "\n")
  end

  # Perfil `byzantine` (não sobe com `up`): é o ÚLTIMO validador, comprometido. Usa a semente dele e responde pelo
  # nome dele na rede (alias), então `mix brdc.compose.equivocate` para o verdadeiro antes. Roda uma vez e sai com
  # o veredito (código 0 = todos os honestos detectaram). Nunca publica porta.
  defp equivocator(o) do
    v = o.validators

    """
      equivocator:
        <<: *brdc
        profiles: [byzantine]
        restart: "no"
        cpus: #{o.cpus}
        mem_limit: #{o.memory}
        memswap_limit: #{o.memory}
        environment:
          <<: *env
          BRDC_ROLE: equivocator
          BRDC_PEER_PORT: "#{@peer_port}"
          BRDC_PUBLIC_PORT: "#{@public_port}"
        volumes:
          - ./net/genesis.json:/net/genesis.json:ro
          - ./net/v#{v}.seed:/run/seed:ro
        networks:
          brdc:
            aliases: [v#{v}]
    """
  end

  defp validator(o, i) do
    """
      v#{i}:
        <<: *brdc
        cpus: #{o.cpus}
        mem_limit: #{o.memory}
        memswap_limit: #{o.memory}
        environment:
          <<: *env
          BRDC_ROLE: validator
          BRDC_INTERVAL_MS: "#{o.interval_ms}"
          BRDC_PEER_PORT: "#{@peer_port}"
          BRDC_PUBLIC_PORT: "#{@public_port}"
        volumes:
          - ./net/genesis.json:/net/genesis.json:ro
          - ./net/v#{i}.seed:/run/seed:ro
          - v#{i}-data:/data
        ports: ["127.0.0.1:#{client_port(o, i)}:#{@public_port}"]
        healthcheck: #{healthcheck(@public_port)}
    """
  end

  # cada carteira aponta para um validador diferente (rodízio), para ver o dado cruzando nós
  defp wallet(o, k) do
    target = rem(k - 1, o.validators) + 1
    port = o.wallet_port + k - 1

    """
      wallet#{k}:
        <<: *brdc
        cpus: #{o.cpus}
        mem_limit: #{o.wallet_memory}
        memswap_limit: #{o.wallet_memory}
        environment:
          <<: *env
          BRDC_ROLE: wallet
          PHX_SERVER: "true"
          PHX_HOST: localhost
          PORT: "#{@web_port}"
          BRDC_NODE_HOST: v#{target}
          BRDC_NODE_PORT: "#{@public_port}"
          BRDC_ALLOWED_ORIGINS: "//localhost:#{port}"
        ports: ["127.0.0.1:#{port}:#{@web_port}"]
        depends_on: [v#{target}]
        healthcheck: #{healthcheck(@web_port)}
    """
  end

  # só abre a conexão TCP (o bash do container resolve); sem curl na imagem
  defp healthcheck(port) do
    ~s({test: ["CMD-SHELL", "bash -c 'exec 3<>/dev/tcp/127.0.0.1/#{port}'"], interval: 5s, timeout: 3s, retries: 12, start_period: 10s})
  end

  defp volumes(o), do: for(i <- 1..o.validators, do: "  v#{i}-data: {}\n")

  @doc "Arquivo do compose gerado."
  @spec compose_file(Path.t()) :: Path.t()
  def compose_file(dir), do: Path.join(dir, "docker-compose.yml")

  @doc """
  Prepara a pasta `dir` do laboratório: chaves de teste e **gênese** (em `dir/net`, com os nomes dos serviços como
  pares de partida), o `docker-compose.yml`, o `.env` (com um `SECRET_KEY_BASE` de teste) e `lab.json` (as opções,
  para `status`). Nunca sobrescreve chaves nem gênese; o número de validadores é o da gênese e não muda (outro
  número é outra rede: apague a pasta).
  """
  @spec init(Path.t(), keyword()) :: {:ok, opts()} | {:error, term()}
  def init(dir, overrides \\ []) do
    o = Map.merge(defaults(), Map.new(overrides))
    net = Path.join(dir, "net")

    case Devnet.existing_validators(net) do
      n when is_integer(n) and n != o.validators -> {:error, {:validators_mismatch, n}}
      _ -> create(dir, net, o)
    end
  end

  defp create(dir, net, o) do
    File.mkdir_p!(net)

    case Devnet.ensure(net,
           validators: o.validators,
           chain_id: "brdc-lab",
           bootstrap: fn i -> {"v#{i}", @peer_port} end
         ) do
      {:ok, _} -> write_files(dir, o)
      {:error, _} = err -> err
    end
  end

  defp write_files(dir, o) do
    File.write!(compose_file(dir), render(o))
    ensure_env(dir)

    File.write!(
      config_path(dir),
      JSON.encode!(Map.new(o, fn {k, v} -> {Atom.to_string(k), v} end))
    )

    {:ok, o}
  end

  defp ensure_env(dir) do
    path = Path.join(dir, ".env")

    unless File.exists?(path) do
      key = 64 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)
      File.write!(path, "SECRET_KEY_BASE=#{key}\n")
      File.chmod!(path, 0o600)
    end
  end

  @doc "Arquivo com as opções usadas na `init` (lido por `status`)."
  @spec config_path(Path.t()) :: Path.t()
  def config_path(dir), do: Path.join(dir, "lab.json")

  @doc "Opções gravadas pela `init`, ou `nil` se o laboratório ainda não foi criado."
  @spec read_config(Path.t()) :: opts() | nil
  def read_config(dir) do
    with {:ok, text} <- File.read(config_path(dir)),
         {:ok, map} <- JSON.decode(text) do
      Map.new(defaults(), fn {k, default} -> {k, Map.get(map, Atom.to_string(k), default)} end)
    else
      _ -> nil
    end
  end

  @doc """
  Estado de cada validador lido pela porta que o Docker publica no computador: `{i, resultado}` com
  `{:ok, %{status: .., consensus: ..}}` ou `{:error, motivo}` (parado ou fora do ar).
  """
  @spec status(opts() | map()) :: [{pos_integer(), {:ok, map()} | {:error, term()}}]
  def status(o) do
    for i <- 1..o.validators do
      ep = {~c"127.0.0.1", client_port(o, i)}

      result =
        with {:ok, st} <- Client.status(ep),
             {:ok, cons} <- Client.consensus_info(ep) do
          {:ok, %{status: st, consensus: cons}}
        end

      {i, result}
    end
  end
end
