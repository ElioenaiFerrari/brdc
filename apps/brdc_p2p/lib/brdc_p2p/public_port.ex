defmodule BrdcP2p.PublicPort do
  @moduledoc """
  Porta **pública** do nó (Fase 4): é por onde a carteira e o explorador falam com a rede. Ao
  contrário da porta de pares, **não exige identidade** (qualquer um pode perguntar) e por isso
  é **enxuta e muito limitada**:

  - só 4 tipos de pedido (lista fixa): `1` status, `2` enviar transação, `3` ler bloco, `4` ler conta;
  - tamanho máximo **por tipo** de pedido; excesso bane (`:oversized_frame`);
  - tipo desconhecido ou pedido malformado soma pontos e **derruba** a conexão;
  - teto de conexões por IP e total (`BrdcP2p.Guard`), taxa por conexão (`BrdcP2p.Rate`), prazo
    de inatividade;
  - o conteúdo é decidido pelo `handler` do nó, que roda isolado: se ele falhar, o cliente recebe
    um erro genérico e a conexão segue.

  **Não é cifrada nem autenticada** (ADR-0007/0015): quem usa **reverifica tudo** (assinaturas, certificado
  de commit, provas) e não confia no nó. Resposta: `<<0, corpo>>` (ok) ou `<<1, motivo>>` (erro).
  """
  use GenServer
  alias BrdcP2p.{Frame, Guard, Rate}

  @kinds %{
    1 => {:status, 16},
    2 => {:submit_tx, 65_536},
    3 => {:get_block, 16},
    4 => {:get_account, 64}
  }
  # maior pedido possível = tipo (1 byte) + maior corpo
  @max_request 1 + 65_536
  @idle_ms 10_000

  @type handler :: (atom(), binary() -> {:ok, binary()} | {:error, atom() | String.t()})

  @doc "Tipos aceitos e o tamanho máximo do corpo de cada um."
  @spec kinds() :: %{pos_integer() => {atom(), pos_integer()}}
  def kinds, do: @kinds

  @doc "Opções: `:guard`, `:handler`, `:port`, `:rate`, `:burst`, `:idle_ms`."
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @spec port(GenServer.server()) :: non_neg_integer()
  def port(p), do: GenServer.call(p, :port)

  def stop(p), do: GenServer.stop(p)

  @impl true
  def init(opts) do
    {:ok, l} =
      :gen_tcp.listen(Keyword.get(opts, :port, 0), [
        :binary,
        active: false,
        reuseaddr: true,
        backlog: 128
      ])

    {:ok, sup} = Task.Supervisor.start_link()
    {:ok, {_, port}} = :inet.sockname(l)

    ctx = %{
      guard: Keyword.fetch!(opts, :guard),
      handler: Keyword.fetch!(opts, :handler),
      opts: opts,
      sup: sup
    }

    spawn_link(fn -> accept_loop(l, ctx) end)
    {:ok, %{listener: l, port: port}}
  end

  @impl true
  def handle_call(:port, _from, s), do: {:reply, s.port, s}

  @impl true
  def terminate(_reason, s), do: :gen_tcp.close(s.listener)

  # --- aceitação ----------------------------------------------------------------------

  defp accept_loop(l, ctx) do
    case :gen_tcp.accept(l, 1_000) do
      {:ok, sock} ->
        {:ok, pid} = Task.Supervisor.start_child(ctx.sup, fn -> wait_then_serve(sock, ctx) end)
        :gen_tcp.controlling_process(sock, pid)
        send(pid, :go)
        accept_loop(l, ctx)

      {:error, :closed} ->
        :ok

      {:error, _} ->
        accept_loop(l, ctx)
    end
  end

  defp wait_then_serve(sock, ctx) do
    receive do
      :go -> serve(sock, ctx)
    after
      5_000 -> :gen_tcp.close(sock)
    end
  end

  defp serve(sock, ctx) do
    with {:ok, {ip, _}} <- :inet.peername(sock),
         {:ok, id} <- Guard.admit(ctx.guard, ip) do
      rate =
        Rate.new(
          Keyword.get(ctx.opts, :rate, 20),
          Keyword.get(ctx.opts, :burst, 40),
          Guard.now(ctx.guard)
        )

      try do
        loop(sock, id, rate, ctx)
      after
        :gen_tcp.close(sock)
        Guard.release(ctx.guard, id)
      end
    else
      _ -> :gen_tcp.close(sock)
    end
  end

  # --- um pedido por vez ----------------------------------------------------------------

  defp loop(sock, id, rate, ctx) do
    idle = Keyword.get(ctx.opts, :idle_ms, @idle_ms)

    with {:ok, header} <- :gen_tcp.recv(sock, 4, idle),
         {:ok, n} <- parse_header(header, ctx, id),
         {:ok, body} <- recv_body(sock, n, idle),
         {:ok, rate} <- take(rate, ctx, id, sock),
         {:ok, kind, payload} <- classify(body, ctx, id) do
      reply(sock, answer(ctx.handler, kind, payload))
      loop(sock, id, rate, ctx)
    else
      _ -> :closed
    end
  end

  defp parse_header(header, ctx, id) do
    case Frame.parse_header(header, @max_request) do
      {:ok, n} when n >= 1 ->
        {:ok, n}

      {:ok, _} ->
        penalize(ctx, id, :malformed)

      {:error, :too_large} ->
        penalize(ctx, id, :oversized_frame)

      {:error, _} ->
        penalize(ctx, id, :malformed)
    end
  end

  defp recv_body(sock, n, idle), do: :gen_tcp.recv(sock, n, idle)

  defp take(rate, ctx, id, sock) do
    case Rate.take(rate, Guard.now(ctx.guard)) do
      {:ok, r} ->
        {:ok, r}

      {:error, :limited} ->
        reply(sock, {:error, "rate_limited"})
        penalize(ctx, id, :rate_exceeded)
    end
  end

  defp classify(<<tag, payload::binary>>, ctx, id) do
    case Map.fetch(@kinds, tag) do
      {:ok, {kind, max}} when byte_size(payload) <= max -> {:ok, kind, payload}
      {:ok, _} -> penalize(ctx, id, :oversized_frame)
      :error -> penalize(ctx, id, :malformed)
    end
  end

  # devolve :stop (o `with` cai no else e a conexão fecha) depois de registrar a ofensa
  defp penalize(ctx, id, reason) do
    Guard.penalize(ctx.guard, id, reason)
    :stop
  end

  # o handler do nó roda isolado: falha dele vira erro genérico, sem derrubar a conexão
  defp answer(handler, kind, payload) do
    handler.(kind, payload)
  rescue
    _ -> {:error, "internal"}
  catch
    _, _ -> {:error, "internal"}
  end

  defp reply(sock, {:ok, body}), do: send_frame(sock, <<0, body::binary>>)
  defp reply(sock, {:error, reason}), do: send_frame(sock, <<1, to_string(reason)::binary>>)

  defp send_frame(sock, payload) do
    case Frame.encode(payload, 16 * 1_048_576) do
      {:ok, iodata} -> :gen_tcp.send(sock, iodata)
      {:error, _} -> :gen_tcp.send(sock, [<<0, 0, 0, 9>>, <<1, "too_big">>])
    end
  end

  # --- cliente ---------------------------------------------------------------------------

  @doc "Faz um pedido a um nó e lê a resposta (para testes e ferramentas)."
  @spec request(charlist() | :inet.ip_address(), :inet.port_number(), atom(), binary(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def request(host, port, kind, body, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 3_000)

    {tag, _} =
      Enum.find_value(@kinds, fn {t, {k, _}} -> if k == kind, do: {t, k} end) || {255, nil}

    with {:ok, sock} <- :gen_tcp.connect(host, port, [:binary, active: false], timeout) do
      try do
        exchange(sock, <<tag, body::binary>>, timeout)
      after
        :gen_tcp.close(sock)
      end
    end
  end

  defp exchange(sock, payload, timeout) do
    with {:ok, iodata} <- Frame.encode(payload, 16 * 1_048_576),
         :ok <- :gen_tcp.send(sock, iodata),
         {:ok, <<n::32>>} <- :gen_tcp.recv(sock, 4, timeout),
         {:ok, resp} <- :gen_tcp.recv(sock, n, timeout) do
      case resp do
        <<0, rest::binary>> -> {:ok, rest}
        <<1, reason::binary>> -> {:error, reason}
        _ -> {:error, :malformed_response}
      end
    end
  end
end
