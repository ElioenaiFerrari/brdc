defmodule BrdcP2p.ListenerTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.Ed25519
  alias BrdcP2p.{Channel, Guard, Limits, Listener, Session}

  @genesis :crypto.hash(:sha256, "genesis-l")

  defp seed(n), do: :crypto.hash(:sha256, "listener-validator-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))

  defp cfg(n, vals),
    do: %{
      seed: seed(n),
      chain_id: "brdc-test",
      genesis_hash: @genesis,
      validators: fn -> vals end
    }

  # handler: avisa "ready" e devolve eco até o par sair ou errar
  defp echo(session) do
    Session.send(session, "ready")
    loop(session)
  end

  defp loop(s) do
    case Session.recv(s, 3_000) do
      {:ok, bin, s} ->
        Session.send(s, "eco:" <> bin)
        loop(s)

      {:error, _, _} ->
        :done
    end
  end

  defp start(limit_opts, listener_opts \\ []) do
    vals = [pub(1), pub(2), pub(3)]
    {:ok, guard} = Guard.start_link(Keyword.merge([sweep_ms: :never], limit_opts))

    {:ok, l} =
      Listener.start_link(
        Keyword.merge([config: cfg(1, vals), guard: guard, handler: &echo/1], listener_opts)
      )

    on_exit(fn -> if Process.alive?(l), do: Listener.stop(l) end)
    {guard, Listener.port(l), vals}
  end

  # conecta e espera o "ready"; `{:ok, conn}` só se o servidor admitiu a sessão
  defp join(port, n, vals) do
    with {:ok, conn} <- Channel.connect(~c"127.0.0.1", port, cfg(n, vals), timeout: 3_000),
         {:ok, "ready"} <- Channel.recv_frame(conn, 1_500) do
      {:ok, conn}
    end
  end

  defp wait_until(fun, tries \\ 40) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(25) && wait_until(fun, tries - 1)
    end
  end

  test "validador do conjunto entra e conversa" do
    {_g, port, vals} = start([])
    assert {:ok, conn} = join(port, 2, vals)
    Channel.send_frame(conn, "oi")
    assert {:ok, "eco:oi"} = Channel.recv_frame(conn, 2_000)
    Channel.close(conn)
  end

  test "teto por chave: a terceira conexão da mesma chave é recusada" do
    {guard, port, vals} = start(max_per_key: 2)
    assert {:ok, c1} = join(port, 2, vals)
    assert {:ok, c2} = join(port, 2, vals)
    assert {:error, _} = join(port, 2, vals)
    # outra chave ainda entra
    assert {:ok, c3} = join(port, 3, vals)
    assert Limits.count(Guard.state(guard), :key, pub(2)) == 2
    for c <- [c1, c2, c3], do: Channel.close(c)
  end

  test "teto por IP: acima do limite a conexão cai antes do handshake" do
    {_g, port, vals} = start(max_per_ip: 2, max_per_key: 5)
    assert {:ok, c1} = join(port, 2, vals)
    assert {:ok, c2} = join(port, 3, vals)
    assert {:error, _} = join(port, 2, vals)
    for c <- [c1, c2], do: Channel.close(c)
  end

  test "ao fechar, a vaga volta" do
    {guard, port, vals} = start(max_per_key: 1)
    {:ok, c1} = join(port, 2, vals)
    assert {:error, _} = join(port, 2, vals)
    Channel.close(c1)
    assert wait_until(fn -> Limits.count(Guard.state(guard), :key, pub(2)) == 0 end)
    assert {:ok, c2} = join(port, 2, vals)
    Channel.close(c2)
  end

  test "quadro gigante bane a chave; loopback não é banido, então outras chaves seguem entrando" do
    {guard, port, vals} = start([], session_opts: [])
    {:ok, c} = join(port, 2, vals)

    # anuncia 2 MB: acima do limite padrão de 1 MiB por quadro, o que vale banimento imediato
    :ssl.send(c.socket, <<2_000_000::32>>)

    assert wait_until(fn ->
             Limits.banned?(Guard.state(guard), {:key, pub(2)}, Guard.now(guard))
           end)

    Channel.close(c)

    # a chave banida não volta
    assert {:error, _} = join(port, 2, vals)
    # mas o IP (loopback) não foi banido: outra chave entra
    refute Limits.banned?(Guard.state(guard), {:ip, {127, 0, 0, 1}}, Guard.now(guard))
    assert {:ok, c3} = join(port, 3, vals)
    Channel.close(c3)
  end

  test "intruso repetido em loopback não derruba ninguém" do
    {guard, port, vals} = start([])

    for _ <- 1..6 do
      _ = Channel.connect(~c"127.0.0.1", port, cfg(99, vals ++ [pub(99)]), timeout: 2_000)
    end

    refute Limits.banned?(Guard.state(guard), {:ip, {127, 0, 0, 1}}, Guard.now(guard))
    assert {:ok, c} = join(port, 2, vals)
    Channel.close(c)
  end

  test "excesso de taxa vira ponto e a sessão devolve :rate_exceeded" do
    {guard, port, vals} = start([], session_opts: [rate: 0.001, burst: 2])
    {:ok, c} = join(port, 2, vals)
    for _ <- 1..5, do: Channel.send_frame(c, "x")

    assert wait_until(fn ->
             Enum.any?(Guard.state(guard).points, fn {{:key, k}, {p, _}} ->
               k == pub(2) and p >= 20
             end)
           end)

    Channel.close(c)
  end
end
