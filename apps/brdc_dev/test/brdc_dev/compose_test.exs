defmodule BrdcDev.ComposeTest do
  use ExUnit.Case, async: true
  alias BrdcDev.Compose

  # divide o YAML gerado em serviços (blocos que começam com "  nome:" dentro de `services:`)
  defp services(yaml) do
    [_, rest] = String.split(yaml, "\nservices:\n", parts: 2)
    [body, _] = String.split(rest, "\nvolumes:\n", parts: 2)

    Regex.split(~r/^  (?=[a-z0-9]+:\n)/m, body, trim: true)
    |> Map.new(fn block ->
      [name | _] = String.split(block, ":", parts: 2)
      {name, block}
    end)
  end

  test "N validadores e M carteiras geram N + M serviços (mais o equivocador) e N volumes" do
    yaml = Compose.render(%{Compose.defaults() | validators: 7, wallets: 3})
    s = services(yaml)

    assert s |> Map.keys() |> Enum.sort() ==
             ~w(equivocator v1 v2 v3 v4 v5 v6 v7 wallet1 wallet2 wallet3)

    for i <- 1..7, do: assert(yaml =~ "  v#{i}-data: {}")
    refute yaml =~ "v8-data"
  end

  test "TODO serviço tem limite de CPU, de memória (e de swap) e a base limita processos" do
    yaml = Compose.render(Compose.defaults())
    assert yaml =~ "pids_limit: 256"

    for {name, block} <- services(yaml) do
      assert block =~ ~r/cpus: [0-9.]+/, "#{name} sem cpus"
      assert block =~ ~r/mem_limit: \d+[mg]/, "#{name} sem mem_limit"
      assert block =~ ~r/memswap_limit: \d+[mg]/, "#{name} sem memswap_limit"
    end
  end

  test "os limites pedidos aparecem (validador e carteira têm memórias diferentes)" do
    yaml =
      Compose.render(%{Compose.defaults() | cpus: "0.25", memory: "128m", wallet_memory: "300m"})

    s = services(yaml)
    assert s["v1"] =~ "cpus: 0.25"
    assert s["v1"] =~ "mem_limit: 128m"
    assert s["wallet1"] =~ "mem_limit: 300m"
  end

  test "o intervalo de bloco dos validadores é configurável (padrão 1 s) e vai no ambiente" do
    padrao = Compose.render(Compose.defaults())
    assert padrao =~ ~s(BRDC_INTERVAL_MS: "1000")

    rapido = Compose.render(%{Compose.defaults() | interval_ms: 200})
    assert rapido =~ ~s(BRDC_INTERVAL_MS: "200")
    refute rapido =~ ~s(BRDC_INTERVAL_MS: "1000")
  end

  test "portas só em 127.0.0.1, e a porta de pares (4600) nunca é publicada" do
    yaml = Compose.render(Compose.defaults())
    ports = Regex.scan(~r/ports: \["([^"]+)"\]/, yaml) |> Enum.map(&Enum.at(&1, 1))
    assert length(ports) == 6
    assert Enum.all?(ports, &String.starts_with?(&1, "127.0.0.1:"))
    refute yaml =~ ":4600\""
    assert "127.0.0.1:4700:4545" in ports
    assert "127.0.0.1:4703:4545" in ports
    assert "127.0.0.1:4100:4000" in ports
    assert "127.0.0.1:4101:4000" in ports
  end

  test "cada validador monta SÓ a própria semente (nunca a de outro nem a de emissor/autoridade)" do
    yaml = Compose.render(Compose.defaults())

    for {"v" <> n = name, block} <- services(yaml) do
      assert block =~ "./net/v#{n}.seed:/run/seed:ro", "#{name} sem a própria semente"
      seeds = Regex.scan(~r/\.seed/, block)
      assert length(seeds) == 1, "#{name} monta mais de uma semente"
    end

    for forbidden <- ~w(i1.seed i2.seed a1.seed a2.seed), do: refute(yaml =~ forbidden)
  end

  test "carteiras só falam com um validador e em rodízio; sem semente nenhuma" do
    yaml = Compose.render(%{Compose.defaults() | validators: 3, wallets: 4})
    s = services(yaml)
    assert s["wallet1"] =~ "BRDC_NODE_HOST: v1"
    assert s["wallet2"] =~ "BRDC_NODE_HOST: v2"
    assert s["wallet3"] =~ "BRDC_NODE_HOST: v3"
    assert s["wallet4"] =~ "BRDC_NODE_HOST: v1"
    refute s["wallet1"] =~ ".seed"
    assert s["wallet2"] =~ ~s(BRDC_ALLOWED_ORIGINS: "//localhost:4101")
  end

  test "endurecimento: sem privilégios, raiz somente leitura, reinício e verificação de saúde" do
    yaml = Compose.render(Compose.defaults())

    for line <- [
          "cap_drop: [ALL]",
          "no-new-privileges:true",
          "read_only: true",
          "restart: unless-stopped",
          "init: true"
        ],
        do: assert(yaml =~ line)

    # o equivocador roda uma vez e sai: não tem healthcheck
    for {name, block} <- services(yaml),
        name != "equivocator",
        do: assert(block =~ "healthcheck:", "#{name} sem healthcheck")

    assert yaml =~ "+S 2:2"
  end

  test "equivocador: perfil byzantine, sem reinício, SÓ a semente do último validador, com o nome dele, sem portas" do
    yaml = Compose.render(%{Compose.defaults() | validators: 5})
    eq = services(yaml)["equivocator"]

    assert eq =~ "profiles: [byzantine]"
    assert eq =~ ~s(restart: "no")
    assert eq =~ "BRDC_ROLE: equivocator"
    assert eq =~ "./net/v5.seed:/run/seed:ro"
    assert length(Regex.scan(~r/\.seed/, eq)) == 1
    assert eq =~ "aliases: [v5]"
    assert eq =~ ~r/cpus: [0-9.]+/ and eq =~ ~r/mem_limit: \d+[mg]/
    refute eq =~ "ports:"
  end

  test "com menos de 4 validadores não há equivocador (o BFT não tolera um bizantino)" do
    for n <- 1..3 do
      yaml = Compose.render(%{Compose.defaults() | validators: n, wallets: 0})
      refute Map.has_key?(services(yaml), "equivocator"), "equivocador com #{n} validadores"
    end
  end

  test "sem carteiras e com 1 validador também gera" do
    yaml = Compose.render(%{Compose.defaults() | validators: 1, wallets: 0})
    assert services(yaml) |> Map.keys() == ["v1"]
  end
end
