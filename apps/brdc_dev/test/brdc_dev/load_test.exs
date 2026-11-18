defmodule BrdcDev.LoadTest do
  # as partes puras da ferramenta de carga: se elas medirem errado, nenhum número do teste vale
  use ExUnit.Case, async: true
  alias BrdcDev.Load

  describe "percentile/2 (posto mais próximo)" do
    test "casos conhecidos" do
      l = Enum.to_list(1..100)
      assert Load.percentile(l, 0.50) == 50
      assert Load.percentile(l, 0.95) == 95
      assert Load.percentile(l, 0.99) == 99
      assert Load.percentile(l, 1.0) == 100
      assert Load.percentile(l, 0.0) == 1
    end

    test "lista de 1 elemento e lista vazia" do
      assert Load.percentile([7], 0.99) == 7
      assert Load.percentile([], 0.5) == nil
    end

    test "nunca sai do intervalo e é monotônico" do
      l = [3, 9, 9, 14, 40, 41, 100]

      ps = for p <- [0.0, 0.1, 0.5, 0.9, 0.99, 1.0], do: Load.percentile(l, p)
      assert ps == Enum.sort(ps)
      assert Enum.all?(ps, &(&1 in l))
    end
  end

  test "summarize converte microssegundos em milissegundos e ordena sozinho" do
    s = Load.summarize([5_000, 1_000, 3_000, 2_000, 4_000])
    assert %{n: 5, p50: 3.0, max: 5.0} = s
    assert Load.summarize([]) == %{n: 0, p50: nil, p95: nil, p99: nil, max: nil}
  end

  describe "parse_cgroup/1" do
    @sample """
    usage_usec 931004
    user_usec 714916
    nr_periods 31
    nr_throttled 17
    throttled_usec 1199462
    MEM 144101376
    MAX 201326592
    PEAK 148328448
    oom_kill 2
    """

    test "lê o que importa e ignora o resto" do
      c = Load.parse_cgroup(@sample)

      assert c == %{
               usage_usec: 931_004,
               nr_periods: 31,
               nr_throttled: 17,
               throttled_usec: 1_199_462,
               mem: 144_101_376,
               mem_max: 201_326_592,
               mem_peak: 148_328_448,
               oom_kill: 2
             }
    end

    test "kernel sem memory.peak (linha PEAK vazia), lixo e texto vazio não quebram" do
      assert %{mem: 5} = Load.parse_cgroup("MEM 5\nPEAK \nmax 0\nlixo sem numero x")
      refute Map.has_key?(Load.parse_cgroup("MEM 5\nPEAK "), :mem_peak)
      assert Load.parse_cgroup("") == %{}
    end
  end

  test "cgroup_delta: núcleos usados, tempo e fração de períodos em throttle, memória e oom" do
    a = %{
      usage_usec: 1_000_000,
      nr_periods: 10,
      nr_throttled: 1,
      throttled_usec: 100_000,
      mem: 100 * 1_048_576,
      oom_kill: 0
    }

    b = %{
      usage_usec: 6_000_000,
      nr_periods: 210,
      nr_throttled: 101,
      throttled_usec: 2_100_000,
      mem: 150 * 1_048_576,
      mem_peak: 170 * 1_048_576,
      mem_max: 192 * 1_048_576,
      oom_kill: 1
    }

    d = Load.cgroup_delta(a, b, 10)

    # 5 s de CPU em 10 s = 0,5 núcleo; throttle de 2 s; 100 dos 200 períodos novos limitados = 50%
    assert d.cpu_cores == 0.5
    assert d.throttled_s == 2.0
    assert d.throttled_pct == 50.0
    assert {d.mem_mib, d.mem_peak_mib, d.mem_max_mib} == {150.0, 170.0, 192.0}
    assert d.oom_kill == 1
  end

  test "cgroup_delta sem períodos novos não divide por zero" do
    a = %{nr_periods: 5, nr_throttled: 1}
    assert Load.cgroup_delta(a, a, 1).throttled_pct == 0.0
  end

  describe "calendário de envio (carga aberta)" do
    test "send_at_us espaça os envios exatamente 1/taxa" do
      assert Load.send_at_us(0, 4) == 0
      assert Load.send_at_us(1, 4) == 250_000
      assert Load.send_at_us(8, 4) == 2_000_000
    end

    test "offered conta os envios do calendário, inclusive o do instante 0" do
      # 25 tx/s entre 8 remetentes = 3,125 cada; em 10 s: instantes 0, 0,32, ... 9,92 = 32 envios por remetente
      assert Load.offered(25 / 8, 8, 10_000) == 256
      assert Load.offered(10.0, 1, 1_000) == 10
      assert Load.offered(1.0, 8, 20_000) == 160
    end

    test "o total oferecido fica perto da taxa nominal (diferença de no máximo 1 envio por remetente)" do
      for rate <- [10, 25, 50, 100, 200, 400], n <- [1, 4, 8] do
        offered = Load.offered(rate / n, n, 20_000)
        assert offered >= rate * 20 and offered <= rate * 20 + n
      end
    end
  end
end
