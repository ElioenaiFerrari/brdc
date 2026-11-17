defmodule BrdcP2p.Session do
  @moduledoc """
  Sessão com um par autenticado: junta o canal (`BrdcP2p.Channel`), o guarda de limites e a taxa
  por sessão (Fase 4). Cada leitura aplica o limite de tamanho do tipo de mensagem e o balde de
  fichas, e converte falhas em **pontos** (`Guard.penalize/3`): quadro gigante, excesso de taxa e
  mensagem malformada levam ao banimento temporário.
  """
  alias BrdcP2p.{Channel, Guard, Rate}

  @enforce_keys [:conn, :id, :guard, :rate]
  defstruct [:conn, :id, :guard, :rate]

  @type t :: %__MODULE__{}

  @spec new(Channel.t(), pos_integer(), GenServer.server(), keyword()) :: t()
  def new(conn, id, guard, opts \\ []) do
    now = Guard.now(guard)
    rate = Rate.new(Keyword.get(opts, :rate, 50), Keyword.get(opts, :burst, 100), now)
    %__MODULE__{conn: conn, id: id, guard: guard, rate: rate}
  end

  @doc "Chave de consenso do par."
  @spec peer(t()) :: <<_::256>>
  def peer(%__MODULE__{conn: c}), do: c.peer

  @doc "Lê o próximo quadro aplicando taxa e tamanho. Falhas viram pontos."
  @spec recv(t(), timeout()) :: {:ok, binary(), t()} | {:error, term(), t()}
  def recv(%__MODULE__{} = s, timeout \\ 5_000) do
    case Rate.take(s.rate, Guard.now(s.guard)) do
      {:error, :limited} ->
        {:error, :rate_exceeded, penalize(s, :rate_exceeded)}

      {:ok, rate} ->
        s = %{s | rate: rate}

        case Channel.recv_frame(s.conn, timeout) do
          {:ok, bin} -> {:ok, bin, s}
          {:error, :too_large} -> {:error, :too_large, penalize(s, :oversized_frame)}
          {:error, :timeout} -> {:error, :timeout, s}
          {:error, reason} -> {:error, reason, s}
        end
    end
  end

  @doc "Registra uma mensagem malformada (o chamador decodificou e falhou)."
  @spec malformed(t()) :: t()
  def malformed(%__MODULE__{} = s), do: penalize(s, :malformed)

  @doc "Envia um quadro."
  @spec send(t(), binary()) :: :ok | {:error, term()}
  def send(%__MODULE__{conn: c}, payload), do: Channel.send_frame(c, payload)

  @doc "Fecha a sessão e libera a vaga no guarda."
  @spec close(t()) :: :ok
  def close(%__MODULE__{} = s) do
    Channel.close(s.conn)
    Guard.release(s.guard, s.id)
  end

  defp penalize(s, reason) do
    Guard.penalize(s.guard, s.id, reason)
    s
  end
end
