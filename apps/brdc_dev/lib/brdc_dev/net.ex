defmodule BrdcDev.Net do
  @moduledoc """
  A rede de teste local de **vários validadores**, cada um em um processo do sistema (ADR-0012, Fase 7/M5).
  Só desenvolvimento. Aqui ficam a configuração (`net/devnet.json`), os caminhos de cada validador (pasta de
  dados, arquivo de pid e de log) e o controle dos processos.

  Disposição (`net/` é ignorada pelo git):

      net/genesis.json, net/v1.seed … vN.seed, i1/i2/a1/a2   chaves e gênese
      net/devnet.json                                        número de validadores e portas
      net/validators/vK/{data/, node.pid, node.log}          dados, pid e log do validador K

  O validador K escuta pares em `peer_base + K - 1` e clientes (carteira, ferramentas) em
  `public_base + K - 1`; o validador 1 fica na porta pública padrão (4545), então a carteira acha a rede sem
  configurar nada.
  """
  alias BrdcDev.Devnet

  @default_public 4545
  @default_peer 4600

  @type config :: %{
          validators: pos_integer(),
          public_base: pos_integer(),
          peer_base: pos_integer()
        }

  @doc "Pasta da rede (padrão `net/`)."
  @spec dir(keyword()) :: Path.t()
  def dir(opts \\ []), do: opts[:dir] || Devnet.default_dir()

  @spec config_path(Path.t()) :: Path.t()
  def config_path(dir), do: Path.join(dir, "devnet.json")

  @doc "Configuração da rede de vários validadores, ou `nil` se ainda não foi criada."
  @spec read_config(Path.t()) :: config() | nil
  def read_config(dir) do
    with {:ok, text} <- File.read(config_path(dir)),
         {:ok, %{"validators" => n, "public_base" => pb, "peer_base" => qb}} <- JSON.decode(text),
         true <- is_integer(n) and n >= 1 and is_integer(pb) and is_integer(qb) do
      %{validators: n, public_base: pb, peer_base: qb}
    else
      _ -> nil
    end
  end

  @spec write_config(Path.t(), config()) :: :ok | {:error, term()}
  def write_config(dir, cfg) do
    text =
      JSON.encode!(%{
        "validators" => cfg.validators,
        "public_base" => cfg.public_base,
        "peer_base" => cfg.peer_base
      })

    File.write(config_path(dir), text <> "\n")
  end

  @doc "Configuração nova a partir das opções de `devnet.init` (`validators`, `public_port`, `peer_port`)."
  @spec new_config(keyword()) :: config()
  def new_config(opts) do
    %{
      validators: opts[:validators] || 4,
      public_base: opts[:public_port] || @default_public,
      peer_base: opts[:peer_port] || @default_peer
    }
  end

  @spec public_port(config(), pos_integer()) :: pos_integer()
  def public_port(cfg, i), do: cfg.public_base + i - 1

  @spec peer_port(config(), pos_integer()) :: pos_integer()
  def peer_port(cfg, i), do: cfg.peer_base + i - 1

  @doc """
  Endpoint do nó para as ferramentas de cliente: `--port` se vier, senão o validador 1 da rede gerenciada
  (`net/devnet.json`), senão a porta padrão 4545.
  """
  @spec client_endpoint(keyword()) :: {charlist(), pos_integer()}
  def client_endpoint(opts) do
    cfg = opts |> dir() |> read_config()
    {~c"127.0.0.1", opts[:port] || (cfg && cfg.public_base) || @default_public}
  end

  @spec endpoint(config(), pos_integer()) :: {charlist(), pos_integer()}
  def endpoint(cfg, i), do: {~c"127.0.0.1", public_port(cfg, i)}

  # --- caminhos de cada validador -------------------------------------------------------------------------------

  @spec validator_dir(Path.t(), pos_integer()) :: Path.t()
  def validator_dir(dir, i), do: Path.join([dir, "validators", "v#{i}"])

  @spec data_dir(Path.t(), pos_integer()) :: Path.t()
  def data_dir(dir, i), do: Path.join(validator_dir(dir, i), "data")

  @spec pid_path(Path.t(), pos_integer()) :: Path.t()
  def pid_path(dir, i), do: Path.join(validator_dir(dir, i), "node.pid")

  @spec log_path(Path.t(), pos_integer()) :: Path.t()
  def log_path(dir, i), do: Path.join(validator_dir(dir, i), "node.log")

  # --- processos ---------------------------------------------------------------------------------------------------

  @doc "Pid gravado do validador `i` (texto de número) ou `nil`."
  @spec read_pid(Path.t(), pos_integer()) :: String.t() | nil
  def read_pid(dir, i) do
    case File.read(pid_path(dir, i)) do
      {:ok, text} -> parse_pid(text)
      _ -> nil
    end
  end

  @doc "Aceita só números (o conteúdo do arquivo vai para `kill`: nunca passa texto livre)."
  @spec parse_pid(String.t()) :: String.t() | nil
  def parse_pid(text) do
    text = String.trim(text)
    if Regex.match?(~r/\A[0-9]{1,9}\z/, text) and text != "0", do: text, else: nil
  end

  @doc "O processo `pid` existe?"
  @spec alive?(String.t() | nil) :: boolean()
  def alive?(nil), do: false

  def alive?(pid) do
    match?({_, 0}, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))
  end

  @doc "Validador `i` está rodando (pid gravado e vivo)?"
  @spec running?(Path.t(), pos_integer()) :: boolean()
  def running?(dir, i), do: dir |> read_pid(i) |> alive?()

  @doc "A porta TCP local está livre?"
  @spec port_free?(pos_integer()) :: boolean()
  def port_free?(port) do
    case :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  @doc "Manda o sinal TERM ou KILL ao processo."
  @spec signal(String.t(), String.t()) :: :ok
  def signal(pid, sig) when sig in ["TERM", "KILL"] do
    System.cmd("kill", ["-#{sig}", pid], stderr_to_stdout: true)
    :ok
  end

  @doc "Espera `fun` ficar verdadeira (a cada 100 ms) por até `ms`. Devolve se ficou."
  @spec wait_until((-> boolean()), non_neg_integer()) :: boolean()
  def wait_until(fun, ms) do
    deadline = System.monotonic_time(:millisecond) + ms
    do_wait(fun, deadline)
  end

  defp do_wait(fun, deadline) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(100) && do_wait(fun, deadline)
    end
  end

  @doc """
  Duração em milissegundos: número puro (`"500"`), `"500ms"`, `"2s"` ou `"1m"`. Devolve `{:ok, ms}` ou `:error`.
  """
  @spec parse_duration(String.t()) :: {:ok, pos_integer()} | :error
  def parse_duration(text) when is_binary(text) do
    case Regex.run(~r/\A([0-9]{1,6})(ms|s|m)?\z/, String.trim(text)) do
      [_, n] -> positive(String.to_integer(n))
      [_, n, "ms"] -> positive(String.to_integer(n))
      [_, n, "s"] -> positive(String.to_integer(n) * 1_000)
      [_, n, "m"] -> positive(String.to_integer(n) * 60_000)
      _ -> :error
    end
  end

  defp positive(ms) when ms > 0, do: {:ok, ms}
  defp positive(_), do: :error

  @doc """
  `--help` ou `-h` entre os argumentos: mostra a documentação da tarefa e devolve `true` (a tarefa não deve agir).
  Evita que pedir ajuda dispare, sem querer, uma ação (como apagar o disco).
  """
  @spec help?([String.t()], String.t()) :: boolean()
  def help?(args, doc) do
    if "--help" in args or "-h" in args do
      Mix.shell().info(doc)
      true
    else
      false
    end
  end
end
