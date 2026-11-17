defmodule BrdcP2p.Limits do
  @moduledoc """
  Política de limites e banimento da porta de pares (Fase 4). **Função pura**: o tempo entra
  como argumento (`now`, em ms) e não há processo, soquete nem relógio aqui; por isso a política
  inteira é testável por propriedade.

  - **Tetos de conexão:** total, por IP e por chave de validador.
  - **Pontos por mau comportamento** (handshake falho, `hello` errado, quadro gigante, mensagem
    malformada, excesso de taxa). Ao passar do limite, o par é **banido por um tempo**. Os pontos
    esquecem depois de uma janela sem ofensa.
  - **Loopback nunca é banido por IP** (todos os nós de uma máquina de testes compartilham o
    endereço; banir 127.0.0.1 derrubaria a rede toda). A chave do validador continua sujeita a ban.
  - **Tamanho máximo por tipo de mensagem** (`max_size/1`).
  """

  @type subject :: {:ip, term()} | {:key, binary()}
  @type reason ::
          :handshake_failure
          | :bad_hello
          | :oversized_frame
          | :malformed
          | :rate_exceeded
          | :timeout

  @points %{
    handshake_failure: 25,
    bad_hello: 50,
    oversized_frame: 100,
    malformed: 30,
    rate_exceeded: 20,
    timeout: 10
  }

  @sizes %{
    hello: 512,
    vote: 1_024,
    proposal: 1_048_576,
    tx: 65_536,
    block: 1_048_576,
    address_record: 1_024
  }

  defstruct max_total: 64,
            max_per_ip: 8,
            max_per_key: 2,
            ban_threshold: 100,
            ban_ms: 600_000,
            forget_ms: 300_000,
            next_id: 1,
            conns: %{},
            points: %{},
            bans: %{}

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts \\ []), do: struct!(__MODULE__, opts)

  @doc "Tamanho máximo (bytes) de cada tipo de mensagem; tipo desconhecido não é aceito."
  @spec max_size(atom()) :: pos_integer() | nil
  def max_size(kind), do: Map.get(@sizes, kind)

  @doc "Pontos de cada tipo de ofensa."
  @spec points(reason()) :: pos_integer()
  def points(reason), do: Map.fetch!(@points, reason)

  # --- admissão ---------------------------------------------------------------------

  @doc "Admite uma conexão nova do IP `ip` (antes do handshake). Devolve o `id` da conexão."
  @spec admit(t(), term(), integer()) ::
          {:ok, pos_integer(), t()} | {:error, :banned | :total | :per_ip}
  def admit(%__MODULE__{} = l, ip, now) do
    cond do
      banned?(l, {:ip, ip}, now) ->
        {:error, :banned}

      map_size(l.conns) >= l.max_total ->
        {:error, :total}

      count(l, :ip, ip) >= l.max_per_ip ->
        {:error, :per_ip}

      true ->
        {:ok, l.next_id,
         %{l | next_id: l.next_id + 1, conns: Map.put(l.conns, l.next_id, %{ip: ip, key: nil})}}
    end
  end

  @doc "Depois do handshake, associa a conexão à chave do validador e confere o teto por chave."
  @spec bind_key(t(), pos_integer(), binary(), integer()) ::
          {:ok, t()} | {:error, :banned | :per_key | :unknown}
  def bind_key(%__MODULE__{} = l, id, key, now) do
    case Map.fetch(l.conns, id) do
      :error ->
        {:error, :unknown}

      {:ok, conn} ->
        cond do
          banned?(l, {:key, key}, now) -> {:error, :banned}
          count(l, :key, key) >= l.max_per_key -> {:error, :per_key}
          true -> {:ok, %{l | conns: Map.put(l.conns, id, %{conn | key: key})}}
        end
    end
  end

  @doc "Libera a conexão (sempre, mesmo se falhou)."
  @spec release(t(), pos_integer()) :: t()
  def release(%__MODULE__{} = l, id), do: %{l | conns: Map.delete(l.conns, id)}

  # --- pontos e banimento ------------------------------------------------------------

  @doc """
  Soma os pontos da ofensa à conexão (ao IP e, se já conhecida, à chave). Devolve `:banned` se
  algum dos dois passou do limite. IP de loopback nunca é banido.
  """
  @spec penalize(t(), pos_integer(), reason(), integer()) :: {:ok | :banned, t()}
  def penalize(%__MODULE__{} = l, id, reason, now) do
    case Map.fetch(l.conns, id) do
      :error -> {:ok, l}
      {:ok, %{ip: ip, key: key}} -> penalize_subjects(l, subjects(ip, key), points(reason), now)
    end
  end

  @doc "Penaliza um IP que nem chegou a ter conexão admitida (ex.: handshake recusado)."
  @spec penalize_ip(t(), term(), reason(), integer()) :: {:ok | :banned, t()}
  def penalize_ip(%__MODULE__{} = l, ip, reason, now),
    do: penalize_subjects(l, subjects(ip, nil), points(reason), now)

  defp subjects(ip, nil), do: if(loopback?(ip), do: [], else: [{:ip, ip}])
  defp subjects(ip, key), do: subjects(ip, nil) ++ [{:key, key}]

  defp penalize_subjects(l, subjects, pts, now) do
    Enum.reduce(subjects, {:ok, l}, fn s, {status, acc} ->
      {st, acc} = add_points(acc, s, pts, now)
      {if(st == :banned, do: :banned, else: status), acc}
    end)
  end

  defp add_points(l, subject, pts, now) do
    {total, last} = Map.get(l.points, subject, {0, now})
    total = if now - last > l.forget_ms, do: 0, else: total
    total = total + pts

    if total >= l.ban_threshold do
      {:banned,
       %{
         l
         | points: Map.delete(l.points, subject),
           bans: Map.put(l.bans, subject, now + l.ban_ms)
       }}
    else
      {:ok, %{l | points: Map.put(l.points, subject, {total, now})}}
    end
  end

  @doc "O sujeito está banido neste instante? (Ban expira sozinho.)"
  @spec banned?(t(), subject(), integer()) :: boolean()
  def banned?(%__MODULE__{bans: bans}, subject, now) do
    case Map.fetch(bans, subject) do
      {:ok, until} -> now < until
      :error -> false
    end
  end

  @doc "Remove bans vencidos e pontos esquecidos (para o estado não crescer sem limite)."
  @spec sweep(t(), integer()) :: t()
  def sweep(%__MODULE__{} = l, now) do
    %{
      l
      | bans: l.bans |> Enum.filter(fn {_, until} -> now < until end) |> Map.new(),
        points:
          l.points |> Enum.filter(fn {_, {_, last}} -> now - last <= l.forget_ms end) |> Map.new()
    }
  end

  # --- util ---------------------------------------------------------------------------

  @doc "Conexões abertas do IP (`:ip`) ou da chave (`:key`)."
  @spec count(t(), :ip | :key, term()) :: non_neg_integer()
  def count(%__MODULE__{conns: c}, :ip, ip), do: Enum.count(c, fn {_, v} -> v.ip == ip end)
  def count(%__MODULE__{conns: c}, :key, key), do: Enum.count(c, fn {_, v} -> v.key == key end)

  @doc "Endereço de loopback (127.0.0.0/8 ou ::1)?"
  @spec loopback?(term()) :: boolean()
  def loopback?({127, _, _, _}), do: true
  def loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def loopback?(_), do: false
end
