defmodule BrdcP2p.PublicPortTest do
  use ExUnit.Case, async: true
  alias BrdcP2p.{Guard, Limits, PublicPort}

  defp handler(:status, _), do: {:ok, "altura=7"}
  defp handler(:submit_tx, body), do: {:ok, "recebi:" <> Integer.to_string(byte_size(body))}
  defp handler(:get_account, "boom"), do: raise("falha do nó")
  defp handler(:get_account, _), do: {:error, :not_found}
  defp handler(:get_block, n), do: {:ok, String.duplicate("b", 100_000) <> n}

  defp start(limit_opts \\ [], port_opts \\ []) do
    {:ok, guard} = Guard.start_link(Keyword.merge([sweep_ms: :never], limit_opts))

    {:ok, p} =
      PublicPort.start_link(Keyword.merge([guard: guard, handler: &handler/2], port_opts))

    on_exit(fn -> stop_quietly(p) end)
    {guard, PublicPort.port(p)}
  end

  defp ask(port, kind, body), do: PublicPort.request(~c"127.0.0.1", port, kind, body)

  # o processo é ligado ao teste e pode já ter morrido quando o on_exit roda
  defp stop_quietly(pid) do
    PublicPort.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp wait_until(fun, tries \\ 40) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(25) && wait_until(fun, tries - 1)
    end
  end

  test "responde aos 4 tipos de pedido" do
    {_g, port} = start()
    assert {:ok, "altura=7"} = ask(port, :status, "")
    assert {:ok, "recebi:5"} = ask(port, :submit_tx, "12345")
    assert {:error, "not_found"} = ask(port, :get_account, "x")
    assert {:ok, big} = ask(port, :get_block, "1")
    assert byte_size(big) == 100_001
  end

  test "falha do handler vira erro genérico e a conexão continua" do
    {_g, port} = start()
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    send_req = fn tag, body -> :gen_tcp.send(sock, [<<byte_size(body) + 1::32, tag>>, body]) end

    recv = fn ->
      with {:ok, <<n::32>>} <- :gen_tcp.recv(sock, 4, 2_000), do: :gen_tcp.recv(sock, n, 2_000)
    end

    send_req.(4, "boom")
    assert {:ok, <<1, "internal">>} = recv.()
    send_req.(1, "")
    assert {:ok, <<0, "altura=7">>} = recv.()
    :gen_tcp.close(sock)
  end

  test "tipo desconhecido derruba a conexão e libera a vaga" do
    {guard, port} = start()
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :gen_tcp.send(sock, <<2::32, 99, 0>>)
    assert {:error, :closed} = :gen_tcp.recv(sock, 4, 2_000)

    assert wait_until(fn ->
             Guard.state(guard).points != %{} or Guard.state(guard).conns == %{}
           end)
  end

  test "corpo acima do máximo do tipo bane (o IP de loopback não, mas a conexão cai)" do
    {guard, port} = start()
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    # tipo 1 (status) aceita no máximo 16 bytes de corpo
    :gen_tcp.send(sock, [<<101::32, 1>>, String.duplicate("a", 100)])
    assert {:error, :closed} = :gen_tcp.recv(sock, 4, 2_000)
    refute Limits.banned?(Guard.state(guard), {:ip, {127, 0, 0, 1}}, Guard.now(guard))
  end

  test "quadro anunciado gigante é cortado sem ler o conteúdo" do
    {_g, port} = start()
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    :gen_tcp.send(sock, <<500_000_000::32>>)
    assert {:error, :closed} = :gen_tcp.recv(sock, 4, 2_000)
  end

  test "teto por IP: acima dele a conexão é recusada" do
    {_g, port} = start(max_per_ip: 2)
    open = fn -> :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false]) end
    {:ok, a} = open.()
    {:ok, b} = open.()
    Process.sleep(100)
    {:ok, c} = open.()
    assert {:error, :closed} = :gen_tcp.recv(c, 1, 2_000)
    for s <- [a, b], do: :gen_tcp.close(s)
  end

  test "excesso de taxa recebe erro e a conexão cai" do
    {guard, port} = start([], rate: 0.001, burst: 2)
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

    ask = fn ->
      :ok = :gen_tcp.send(sock, <<1::32, 1>>)
      with {:ok, <<n::32>>} <- :gen_tcp.recv(sock, 4, 2_000), do: :gen_tcp.recv(sock, n, 2_000)
    end

    # um pedido por vez: a rajada de 2 passa, o terceiro é recusado e a conexão cai
    assert {:ok, <<0, "altura=7">>} = ask.()
    assert {:ok, <<0, "altura=7">>} = ask.()
    assert {:ok, <<1, "rate_limited">>} = ask.()
    assert {:error, :closed} = :gen_tcp.recv(sock, 4, 2_000)
    assert wait_until(fn -> Guard.state(guard).conns == %{} end)
  end

  test "conexão parada é fechada pelo prazo de inatividade e a vaga volta" do
    {guard, port} = start([], idle_ms: 200)
    {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    assert {:error, :closed} = :gen_tcp.recv(sock, 1, 2_000)
    assert wait_until(fn -> Guard.state(guard).conns == %{} end)
  end

  test "a lista de tipos é fixa e pequena" do
    assert PublicPort.kinds() |> Map.keys() |> Enum.sort() == [1, 2, 3, 4, 5]
  end
end
