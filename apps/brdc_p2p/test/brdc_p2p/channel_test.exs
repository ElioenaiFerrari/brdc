defmodule BrdcP2p.ChannelTest do
  use ExUnit.Case, async: true
  alias BrdcCrypto.Ed25519
  alias BrdcP2p.{Cert, Channel, Frame}

  @genesis :crypto.hash(:sha256, "genesis-a")

  defp seed(n), do: :crypto.hash(:sha256, "p2p-validator-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))

  defp cfg(n, validators, opts \\ []) do
    %{
      seed: seed(n),
      chain_id: Keyword.get(opts, :chain, "brdc-test"),
      genesis_hash: Keyword.get(opts, :genesis, @genesis),
      validators: fn -> validators end
    }
  end

  # sobe um servidor que aceita UMA conexão e devolve o resultado (e eco opcional)
  defp serve(server_cfg, opts \\ []) do
    {:ok, listener} = Channel.listen(server_cfg)
    port = Channel.port(listener)

    task = Task.async(fn -> accept_and_echo(listener, server_cfg, opts) end)

    {port, task, listener}
  end

  defp accept_and_echo(listener, server_cfg, opts) do
    case Channel.accept(listener, server_cfg, Keyword.merge([timeout: 3_000], opts)) do
      {:ok, conn} -> echo(conn)
      {:error, e} -> {:rejected, e}
    end
  end

  defp echo(conn) do
    r = Channel.recv_frame(conn, 2_000)
    with {:ok, msg} <- r, do: Channel.send_frame(conn, "eco:" <> msg)
    Channel.close(conn)
    {:accepted, conn.peer, r}
  end

  defp talk(port, client_cfg, opts \\ []) do
    with {:ok, conn} <-
           Channel.connect(~c"127.0.0.1", port, client_cfg, Keyword.merge([timeout: 3_000], opts)),
         :ok <- Channel.send_frame(conn, "oi"),
         {:ok, reply} <- Channel.recv_frame(conn, 2_000) do
      Channel.close(conn)
      {:ok, reply, conn.peer}
    end
  end

  setup do
    {:ok, vals: [pub(1), pub(2), pub(3)]}
  end

  test "dois validadores do conjunto conversam e cada um vê a chave do outro", %{vals: vals} do
    {port, task, l} = serve(cfg(1, vals))
    assert {:ok, "eco:oi", peer} = talk(port, cfg(2, vals))
    assert peer == pub(1)
    assert {:accepted, server_peer, {:ok, "oi"}} = Task.await(task)
    assert server_peer == pub(2)
    :ssl.close(l)
  end

  test "cliente fora do conjunto é recusado", %{vals: vals} do
    {port, task, l} = serve(cfg(1, vals))
    # o intruso conhece o conjunto, mas a chave dele não está nele
    assert {:error, _} = talk(port, cfg(99, vals))
    assert {:rejected, _} = Task.await(task)
    :ssl.close(l)
  end

  test "servidor impostor é recusado pelo cliente", %{vals: vals} do
    {port, task, l} = serve(cfg(99, vals ++ [pub(99)]))
    assert {:error, _} = talk(port, cfg(2, vals))
    assert {:rejected, _} = Task.await(task)
    :ssl.close(l)
  end

  test "rede ou genesis diferentes se recusam mesmo com chaves do conjunto", %{vals: vals} do
    {port, task, l} = serve(cfg(1, vals))
    assert {:error, _} = talk(port, cfg(2, vals, genesis: :crypto.hash(:sha256, "genesis-b")))
    assert {:rejected, :wrong_network} = Task.await(task)
    :ssl.close(l)

    {port, task, l} = serve(cfg(1, vals))
    assert {:error, _} = talk(port, cfg(2, vals, chain: "outra-rede"))
    assert {:rejected, :wrong_network} = Task.await(task)
    :ssl.close(l)
  end

  test "o conjunto é consultado a cada conexão: rotação vale sem reiniciar" do
    {:ok, agent} = Agent.start_link(fn -> [pub(1), pub(2)] end)
    set = fn -> Agent.get(agent, & &1) end
    server_cfg = %{cfg(1, []) | validators: set}

    {:ok, listener} = Channel.listen(server_cfg)
    port = Channel.port(listener)

    accept_once = fn ->
      Task.async(fn ->
        case Channel.accept(listener, server_cfg, timeout: 3_000) do
          {:ok, c} ->
            _ = Channel.recv_frame(c, 1_000)
            Channel.close(c)
            :ok

          {:error, _} ->
            :recusado
        end
      end)
    end

    # antes da rotação, o validador 3 não é do conjunto: o servidor o recusa
    t = accept_once.()
    _ = Channel.connect(~c"127.0.0.1", port, cfg(3, [pub(1), pub(2), pub(3)]), timeout: 3_000)
    assert Task.await(t) == :recusado

    # validador 3 entra no conjunto (mais de 2/3 aprovaram): agora é aceito
    Agent.update(agent, fn v -> v ++ [pub(3)] end)
    t2 = accept_once.()

    assert {:ok, conn} =
             Channel.connect(~c"127.0.0.1", port, cfg(3, [pub(1), pub(2), pub(3)]),
               timeout: 3_000
             )

    Channel.send_frame(conn, "x")
    assert Task.await(t2) == :ok
    :ssl.close(listener)
  end

  describe "limites" do
    test "quadro acima do limite é recusado antes de ler o conteúdo" do
      assert {:error, :too_large} = Frame.encode(String.duplicate("a", 11), 10)
      assert {:error, :too_large} = Frame.parse_header(<<0xFFFFFFFF::32>>, 1_000)
      assert {:ok, 5} = Frame.parse_header(<<5::32>>, 10)
      assert {:error, :malformed} = Frame.parse_header(<<1, 2>>, 10)
    end

    test "separar quadros de um buffer, com resto parcial e tamanho absurdo" do
      {:ok, a} = Frame.encode("abc")
      {:ok, b} = Frame.encode("de")
      buf = IO.iodata_to_binary([a, b]) <> <<0, 0, 0, 9, "par">>
      assert {:ok, ["abc", "de"], <<0, 0, 0, 9, "par">>} = Frame.split(buf)
      assert {:error, :too_large} = Frame.split(<<0xFFFFFFFF::32, "x">>)
    end

    test "par que anuncia quadro gigante é derrubado sem o servidor ler o conteúdo", %{vals: vals} do
      {:ok, listener} = Channel.listen(cfg(1, vals))
      port = Channel.port(listener)

      task =
        Task.async(fn ->
          with {:ok, c} <- Channel.accept(listener, cfg(1, vals), timeout: 3_000, max_frame: 100),
               do: Channel.recv_frame(c, 2_000)
        end)

      {:ok, conn} =
        Channel.connect(~c"127.0.0.1", port, cfg(2, vals), timeout: 3_000, max_frame: 10_000)

      :ssl.send(conn.socket, <<1_000_000::32>>)
      assert {:error, :too_large} = Task.await(task)
      :ssl.close(listener)
    end

    test "par calado estoura o prazo de leitura", %{vals: vals} do
      {:ok, listener} = Channel.listen(cfg(1, vals))
      port = Channel.port(listener)

      task =
        Task.async(fn ->
          with {:ok, c} <- Channel.accept(listener, cfg(1, vals), timeout: 3_000),
               do: Channel.recv_frame(c, 300)
        end)

      {:ok, conn} = Channel.connect(~c"127.0.0.1", port, cfg(2, vals), timeout: 3_000)
      assert {:error, :timeout} = Task.await(task)
      Channel.close(conn)
      :ssl.close(listener)
    end
  end

  describe "certificado" do
    test "carrega a chave de consenso e só aceita Ed25519" do
      c = Cert.generate(seed(1))
      assert c.public_key == pub(1)
      assert {:ok, pub(1)} == Cert.public_key(c.der)
      assert :error == Cert.public_key("lixo")
      assert :error == Cert.public_key(<<>>)
    end
  end
end
