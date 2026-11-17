defmodule BrdcP2p.LimitsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcP2p.{Limits, Rate}

  @ip {10, 0, 0, 1}
  @key <<1::256>>

  defp admit!(l, ip, now \\ 0) do
    {:ok, id, l} = Limits.admit(l, ip, now)
    {id, l}
  end

  describe "tetos de conexão" do
    test "por IP, total e por chave" do
      l = Limits.new(max_per_ip: 2, max_total: 3, max_per_key: 1)
      {a, l} = admit!(l, @ip)
      {_b, l} = admit!(l, @ip)
      assert {:error, :per_ip} = Limits.admit(l, @ip, 0)
      {_c, l} = admit!(l, {10, 0, 0, 2})
      assert {:error, :total} = Limits.admit(l, {10, 0, 0, 3}, 0)

      assert {:ok, l} = Limits.bind_key(l, a, @key, 0)
      {d, l} = admit!(Limits.release(l, 3), {10, 0, 0, 4})
      assert {:error, :per_key} = Limits.bind_key(l, d, @key, 0)
    end

    test "liberar devolve a vaga" do
      l = Limits.new(max_per_ip: 1)
      {id, l} = admit!(l, @ip)
      assert {:error, :per_ip} = Limits.admit(l, @ip, 0)
      assert {:ok, _, _} = Limits.admit(Limits.release(l, id), @ip, 0)
    end

    test "bind_key de conexão desconhecida" do
      assert {:error, :unknown} = Limits.bind_key(Limits.new(), 99, @key, 0)
    end
  end

  describe "pontos e banimento" do
    test "ofensas somam até o limite e então banem; o ban expira" do
      l = Limits.new(ban_threshold: 100, ban_ms: 1_000)
      {id, l} = admit!(l, @ip)
      {:ok, l} = Limits.penalize(l, id, :malformed, 0)
      {:ok, l} = Limits.penalize(l, id, :malformed, 10)
      {:ok, l} = Limits.penalize(l, id, :malformed, 20)
      assert {:banned, l} = Limits.penalize(l, id, :malformed, 30)
      assert Limits.banned?(l, {:ip, @ip}, 500)
      assert {:error, :banned} = Limits.admit(l, @ip, 500)
      refute Limits.banned?(l, {:ip, @ip}, 1_031)
      assert {:ok, _, _} = Limits.admit(l, @ip, 1_031)
    end

    test "quadro gigante bane de uma vez" do
      l = Limits.new()
      {id, l} = admit!(l, @ip)
      assert {:banned, _} = Limits.penalize(l, id, :oversized_frame, 0)
    end

    test "pontos são esquecidos depois da janela sem ofensa" do
      l = Limits.new(forget_ms: 1_000)
      {id, l} = admit!(l, @ip)
      {:ok, l} = Limits.penalize(l, id, :bad_hello, 0)
      assert {:ok, l} = Limits.penalize(l, id, :timeout, 5_000)
      refute Limits.banned?(l, {:ip, @ip}, 5_000)
    end

    test "loopback nunca é banido por IP, mas a chave sim" do
      l = Limits.new()
      {id, l} = admit!(l, {127, 0, 0, 1})
      {:ok, l} = Limits.bind_key(l, id, @key, 0)
      assert {:banned, l} = Limits.penalize(l, id, :oversized_frame, 0)
      refute Limits.banned?(l, {:ip, {127, 0, 0, 1}}, 1)
      assert Limits.banned?(l, {:key, @key}, 1)
      assert {:ok, _, _} = Limits.admit(l, {127, 0, 0, 1}, 1)
      assert Limits.loopback?({0, 0, 0, 0, 0, 0, 0, 1})
      refute Limits.loopback?({10, 0, 0, 1})
    end

    test "IP sem conexão (handshake recusado) também acumula pontos" do
      l = Limits.new()

      l =
        Enum.reduce(1..3, l, fn _, acc ->
          {:ok, acc} = Limits.penalize_ip(acc, @ip, :handshake_failure, 0)
          acc
        end)

      assert {:banned, l} = Limits.penalize_ip(l, @ip, :handshake_failure, 0)
      assert Limits.banned?(l, {:ip, @ip}, 1)
    end

    test "sweep remove bans vencidos e pontos esquecidos" do
      l = Limits.new(ban_ms: 100, forget_ms: 100)
      {:banned, l} = Limits.penalize_ip(l, @ip, :oversized_frame, 0)
      {:ok, l} = Limits.penalize_ip(l, {10, 0, 0, 9}, :timeout, 0)
      l = Limits.sweep(l, 1_000)
      assert l.bans == %{} and l.points == %{}
    end

    test "tamanho máximo por tipo de mensagem" do
      assert Limits.max_size(:vote) < Limits.max_size(:block)
      assert Limits.max_size(:desconhecido) == nil
    end
  end

  defp op_gen do
    one_of([
      tuple({constant(:admit), integer(1..4)}),
      tuple({constant(:release), integer(1..30)})
    ])
  end

  defp apply_op({:admit, n}, acc) do
    case Limits.admit(acc, {10, 0, 0, n}, 0) do
      {:ok, _, acc} -> acc
      {:error, _} -> acc
    end
  end

  defp apply_op({:release, id}, acc), do: Limits.release(acc, id)

  property "os tetos nunca são ultrapassados, em qualquer sequência de operações" do
    check all(ops <- list_of(op_gen(), max_length: 80), max_runs: 100) do
      l = Enum.reduce(ops, Limits.new(max_total: 6, max_per_ip: 2), &apply_op/2)

      assert map_size(l.conns) <= 6
      for n <- 1..4, do: assert(Limits.count(l, :ip, {10, 0, 0, n}) <= 2)
    end
  end

  describe "balde de fichas" do
    test "rajada, recusa e reposição com o tempo" do
      b = Rate.new(1, 2, 0)
      {:ok, b} = Rate.take(b, 0)
      {:ok, b} = Rate.take(b, 0)
      assert {:error, :limited} = Rate.take(b, 0)
      assert {:ok, _} = Rate.take(b, 1_000)
    end

    defp run_takes(times) do
      {ok, _} =
        Enum.reduce(times, {0, Rate.new(2, 5, 0)}, fn t, {n, b} ->
          case Rate.take(b, t) do
            {:ok, b} -> {n + 1, b}
            {:error, _} -> {n, b}
          end
        end)

      ok
    end

    property "nunca passa da taxa: em T segundos cabem no máximo burst + rate*T" do
      check all(times <- list_of(integer(0..10_000), max_length: 100)) do
        times = Enum.sort(times)
        horizon = (List.last(times) || 0) / 1000
        assert run_takes(times) <= 5 + 2 * horizon + 1
      end
    end
  end
end
