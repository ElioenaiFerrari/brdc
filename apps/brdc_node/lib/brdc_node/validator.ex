defmodule BrdcNode.Validator do
  @moduledoc """
  Sobe **um validador** a partir de arquivos: a gênese (`genesis.json`, pública, igual em todos os computadores)
  e a **semente** do validador (`NOME.seed`, privada, 0600, nunca sai da máquina). É o que `mix brdc.validator`
  usa, e o que permite rodar a mesma rede em computadores diferentes.

  Os pares vêm do `bootstrap` da gênese (onde achar cada validador: `host:porta`); o validador não disca para si.
  Escuta em **todas as interfaces** (precisa, para o outro computador chegar): a porta de **pares** só aceita
  validadores da gênese (TLS 1.3 mútuo com a chave de consenso) e a porta **pública** serve clientes
  (carteira, explorador) com limites por IP. Em rede de teste, libere só as duas portas no firewall.
  """
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcNode.{Genesis, Handler, Keygen, Node, Replica}
  alias BrdcP2p.{Guard, PublicPort}

  @type started :: %{
          node: pid(),
          replica: pid(),
          public_port: pid(),
          address: String.t(),
          genesis_hash: String.t(),
          index: pos_integer(),
          peer_port: pos_integer(),
          client_port: pos_integer(),
          peers: [map()]
        }

  @doc """
  Opções: `genesis:` e `seed:` (caminhos), `data_dir:`, `peer_port:`, `public_port:` (0 = qualquer livre) e
  `interval_ms:`. Fica ligado ao processo que chamou.
  """
  @spec start(keyword()) :: {:ok, started()} | {:error, term()}
  def start(opts) do
    with {:ok, text} <- read(Keyword.fetch!(opts, :genesis), :genesis),
         {:ok, genesis} <- Genesis.from_json(text),
         {:ok, seed} <- Keygen.load_seed(Keyword.fetch!(opts, :seed)),
         pub = Ed25519.public_key(seed),
         {:ok, index} <- index_of(genesis, pub) do
      launch(genesis, seed, pub, index, opts)
    end
  end

  defp read(path, what) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, {what, path, reason}}
    end
  end

  defp index_of(genesis, pub) do
    case Enum.find_index(genesis.validators, &(&1 == pub)) do
      nil -> {:error, :not_a_validator}
      i -> {:ok, i + 1}
    end
  end

  defp launch(genesis, seed, pub, index, opts) do
    data = Keyword.fetch!(opts, :data_dir)
    File.mkdir_p!(data)

    peers =
      for b <- genesis.bootstrap, b.validator != pub do
        %{pub: b.validator, host: b.host, port: b.port}
      end

    {:ok, node} =
      Node.start_link(genesis: genesis, seed: seed, block_interval_ms: :manual, data_dir: data)

    {:ok, replica} =
      Replica.start_link(
        node: node,
        genesis: genesis,
        seed: seed,
        data_dir: data,
        port: Keyword.get(opts, :peer_port, 0),
        peers: peers,
        interval_ms: Keyword.get(opts, :interval_ms, 1_000)
      )

    {:ok, guard} = Guard.start_link(sweep_ms: 60_000)

    {:ok, public} =
      PublicPort.start_link(
        guard: guard,
        handler: Handler.fun(node),
        port: Keyword.get(opts, :public_port, 0)
      )

    {:ok,
     %{
       node: node,
       replica: replica,
       public_port: public,
       address: Address.from_public_key(pub),
       genesis_hash: genesis |> Genesis.hash() |> Base.encode16(case: :lower),
       index: index,
       peer_port: Replica.port(replica),
       client_port: PublicPort.port(public),
       peers: peers
     }}
  end
end
