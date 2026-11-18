defmodule BrdcNode.PeersTest do
  # rede real (TLS) com prazos curtos: roda sozinho, sem competir por CPU com os outros módulos
  use ExUnit.Case, async: false
  alias BrdcConsensus.Vote
  alias BrdcCrypto.Ed25519
  alias BrdcNode.{Genesis, Peers}
  alias BrdcP2p.Guard

  @chain "peers-test"

  defp seed(n), do: :crypto.hash(:sha256, "peers-#{n}")
  defp pub(n), do: Ed25519.public_key(seed(n))

  defp genesis(validators) do
    {:ok, g} =
      Genesis.new(
        chain_id: @chain,
        validators: Enum.map(validators, &pub/1),
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2
      )

    g
  end

  # sobe o Peers do validador `n`; `owner` recebe os eventos
  defp start_peers(n, g, peers, owner, extra \\ []) do
    {:ok, guard} = Guard.start_link(sweep_ms: :never)
    start_supervised!({Agent, fn -> :ok end}, id: {:agent, n, System.unique_integer()})

    {:ok, p} =
      Peers.start_link(
        Keyword.merge(
          [genesis: g, seed: seed(n), owner: owner, guard: guard, peers: peers, retry_ms: 50],
          extra
        )
      )

    # o Peers pode já ter saído sozinho (o pai, o teste, terminou): a limpeza tolera isso
    on_exit(fn ->
      try do
        GenServer.stop(p)
      catch
        :exit, _ -> :ok
      end
    end)

    p
  end

  # (menor, maior): quem tem a chave menor disca
  defp ordered(a, b), do: if(pub(a) < pub(b), do: {a, b}, else: {b, a})

  test "o de chave menor disca o de maior; os dois ficam conectados e trocam mensagens nos dois sentidos" do
    {lo, hi} = ordered(1, 2)
    g = genesis([1, 2])
    hi_p = start_peers(hi, g, [], self())

    lo_p =
      start_peers(lo, g, [%{pub: pub(hi), host: "127.0.0.1", port: Peers.port(hi_p)}], self())

    assert_receive {:peer_up, _}, 3_000
    assert_receive {:peer_up, _}, 3_000
    assert Peers.connected(lo_p) == [pub(hi)]
    assert Peers.connected(hi_p) == [pub(lo)]

    Peers.broadcast(lo_p, {:status, 5, nil})
    assert_receive {:peer_msg, from, {:status, 5, nil}}, 2_000
    assert from == pub(lo)

    Peers.broadcast(hi_p, {:tx, "ola"})
    assert_receive {:peer_msg, from2, {:tx, "ola"}}, 2_000
    assert from2 == pub(hi)
  end

  test "ordem preservada em muitas mensagens e send_to só vai ao par pedido" do
    {lo, hi} = ordered(1, 2)
    g = genesis([1, 2])
    hi_p = start_peers(hi, g, [], self())

    lo_p =
      start_peers(lo, g, [%{pub: pub(hi), host: "127.0.0.1", port: Peers.port(hi_p)}], self())

    # os DOIS lados precisam estar registrados antes de transmitir (senão o broadcast não tem para quem ir)
    assert_receive {:peer_up, _}, 3_000
    assert_receive {:peer_up, _}, 3_000

    for i <- 1..200, do: Peers.send_to(lo_p, pub(hi), {:status, i, nil})

    got =
      for _ <- 1..200 do
        receive do
          {:peer_msg, _, {:status, i, nil}} -> i
        after
          2_000 -> :timeout
        end
      end

    assert got == Enum.to_list(1..200)
    # par desconhecido: ignorado sem erro
    Peers.send_to(lo_p, pub(9), {:status, 1, nil})
  end

  test "quando o par cai avisa peer_down; ao voltar na mesma porta, reconecta sozinho" do
    {lo, hi} = ordered(1, 2)
    g = genesis([1, 2])
    port = free_port()
    hi_p = start_peers(hi, g, [], self(), port: port)
    lo_p = start_peers(lo, g, [%{pub: pub(hi), host: "127.0.0.1", port: port}], self())
    assert_receive {:peer_up, _}, 3_000
    assert_receive {:peer_up, _}, 3_000

    GenServer.stop(hi_p)
    assert_receive {:peer_down, p}, 3_000
    assert p == pub(hi)
    assert Peers.connected(lo_p) == []

    # o par volta na MESMA porta: o discador reconecta sem ninguém pedir
    _hi2 = start_peers(hi, g, [], self(), port: port)
    assert_receive {:peer_up, _}, 5_000
    assert_eventually(fn -> Peers.connected(lo_p) == [pub(hi)] end)
  end

  test "mensagem malformada derruba a sessão (e o par reconecta depois)" do
    {lo, hi} = ordered(1, 2)
    g = genesis([1, 2])
    hi_p = start_peers(hi, g, [], self())

    lo_p =
      start_peers(lo, g, [%{pub: pub(hi), host: "127.0.0.1", port: Peers.port(hi_p)}], self())

    assert_receive {:peer_up, _}, 3_000
    assert_receive {:peer_up, _}, 3_000

    # envia bytes que não são uma mensagem válida, direto pelo canal (ignora o Wire)
    :sys.get_state(lo_p)
    send_raw(lo_p, pub(hi), <<99, "isso nao e wire">>)
    assert_receive {:peer_down, _}, 3_000
    refute_receive {:peer_msg, _, _}, 100
  end

  test "quem não é validador não consegue conectar" do
    {lo, hi} = ordered(1, 2)
    g = genesis([1, 2])
    hi_p = start_peers(hi, g, [], self())

    # o estranho (chave 3) tem a gênese que o lista como validador... mas a do `hi` não o conhece
    {:ok, strange_genesis} =
      Genesis.new(
        chain_id: @chain,
        validators: [pub(lo), pub(hi), pub(3)],
        issuers: [pub(10), pub(11)],
        threshold: 2,
        authorities: [pub(20), pub(21)],
        authority_threshold: 2
      )

    me =
      start_peers(
        3,
        strange_genesis,
        [%{pub: pub(hi), host: "127.0.0.1", port: Peers.port(hi_p)}],
        self()
      )

    refute_receive {:peer_up, _}, 600
    assert Peers.connected(me) == []
    assert Peers.connected(hi_p) == []
  end

  test "mensagens de vários tipos chegam decodificadas (voto assinado)" do
    {lo, hi} = ordered(1, 2)
    g = genesis([1, 2])
    hi_p = start_peers(hi, g, [], self())

    lo_p =
      start_peers(lo, g, [%{pub: pub(hi), host: "127.0.0.1", port: Peers.port(hi_p)}], self())

    # os DOIS lados precisam estar registrados antes de transmitir (senão o broadcast não tem para quem ir)
    assert_receive {:peer_up, _}, 3_000
    assert_receive {:peer_up, _}, 3_000
    v = Vote.sign(@chain, :prevote, 1, 0, nil, seed(lo))
    Peers.broadcast(lo_p, {:vote, v})
    assert_receive {:peer_msg, _, {:vote, ^v}}, 2_000
  end

  # --- auxiliares ------------------------------------------------------------------------------

  defp free_port do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)
    port
  end

  defp assert_eventually(fun, tries \\ 40) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("a condição não ficou verdadeira")
      true -> Process.sleep(50) && assert_eventually(fun, tries - 1)
    end
  end

  # escreve bytes crus na sessão do par (para simular um par mal-comportado)
  defp send_raw(peers, pub, bin) do
    %{sessions: sessions} = :sys.get_state(peers)
    send(Map.fetch!(sessions, pub), {:send, bin})
  end
end
