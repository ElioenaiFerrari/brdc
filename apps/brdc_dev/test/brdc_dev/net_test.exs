defmodule BrdcDev.NetTest do
  use ExUnit.Case, async: true
  alias BrdcDev.{Devnet, Net}

  @moduletag :tmp_dir

  test "configuração: ida e volta, padrões e portas por validador", %{tmp_dir: dir} do
    assert Net.read_config(dir) == nil
    cfg = Net.new_config(validators: 4)
    assert cfg == %{validators: 4, public_base: 4545, peer_base: 4600}
    :ok = Net.write_config(dir, cfg)
    assert Net.read_config(dir) == cfg
    assert Net.public_port(cfg, 1) == 4545 and Net.public_port(cfg, 4) == 4548
    assert Net.peer_port(cfg, 2) == 4601
    assert Net.endpoint(cfg, 3) == {~c"127.0.0.1", 4547}
    assert Net.new_config(validators: 2, public_port: 6000, peer_port: 7000).public_base == 6000
  end

  test "configuração ilegível ou incompleta vale como inexistente", %{tmp_dir: dir} do
    File.write!(Net.config_path(dir), "lixo")
    assert Net.read_config(dir) == nil
    File.write!(Net.config_path(dir), ~s({"validators": 0, "public_base": 1, "peer_base": 2}))
    assert Net.read_config(dir) == nil
    File.write!(Net.config_path(dir), ~s({"validators": "4"}))
    assert Net.read_config(dir) == nil
  end

  test "caminhos de cada validador ficam sob a pasta dele", %{tmp_dir: dir} do
    v = Net.validator_dir(dir, 3)
    assert String.ends_with?(v, "validators/v3")

    for p <- [Net.data_dir(dir, 3), Net.pid_path(dir, 3), Net.log_path(dir, 3)],
        do: assert(String.starts_with?(p, v))
  end

  test "pid: só número entra (o conteúdo do arquivo vai para o kill)" do
    assert Net.parse_pid("1234\n") == "1234"
    assert Net.parse_pid(" 7 ") == "7"

    for bad <- ["", "0", "abc", "12 34", "12;rm -rf /", "-1", "1234567890", "$(x)"],
        do: assert(Net.parse_pid(bad) == nil)
  end

  test "processo: o próprio pid está vivo; pid inexistente ou nulo não", %{tmp_dir: dir} do
    assert Net.alive?(System.pid())
    refute Net.alive?(nil)
    refute Net.alive?("999999")
    refute Net.running?(dir, 1)
    File.mkdir_p!(Net.validator_dir(dir, 1))
    File.write!(Net.pid_path(dir, 1), System.pid() <> "\n")
    assert Net.running?(dir, 1)
    File.write!(Net.pid_path(dir, 1), "lixo\n")
    refute Net.running?(dir, 1)
  end

  test "duração: número, ms, s, m; o resto é recusado" do
    assert Net.parse_duration("500") == {:ok, 500}
    assert Net.parse_duration("500ms") == {:ok, 500}
    assert Net.parse_duration("2s") == {:ok, 2_000}
    assert Net.parse_duration(" 1m ") == {:ok, 60_000}

    for bad <- ["", "0", "0s", "-1", "1h", "s", "1.5s", "1 s", "9999999"],
        do: assert(Net.parse_duration(bad) == :error)
  end

  test "porta: livre quando ninguém usa; ocupada quando alguém escuta" do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    refute Net.port_free?(port)
    :gen_tcp.close(l)
    assert Net.port_free?(port)
  end

  test "espera: devolve verdadeiro assim que a condição vale e falso no prazo" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)
    assert Net.wait_until(fn -> Agent.get_and_update(agent, &{&1 >= 2, &1 + 1}) end, 2_000)
    refute Net.wait_until(fn -> false end, 250)
  end

  test "--help mostra a ajuda e NÃO deixa a tarefa agir" do
    assert Net.help?(["--all", "--help"], "ajuda") == true
    assert Net.help?(["-h"], "ajuda") == true
    assert Net.help?(["--all"], "ajuda") == false
  end

  test "gênese de N validadores: chaves v1..vN, ordem estável e número fixo depois de criada", %{
    tmp_dir: dir
  } do
    assert Devnet.existing_validators(dir) == nil
    {:ok, dn} = Devnet.ensure(dir, validators: 4)
    assert length(dn.genesis.validators) == 4

    assert Enum.sort(Map.keys(dn.seeds)) ==
             Enum.sort(["v1", "v2", "v3", "v4", "i1", "i2", "a1", "a2"])

    assert Devnet.existing_validators(dir) == 4

    # a ordem dos validadores na gênese é a de v1..vN (o rodízio do consenso depende dela)
    for i <- 1..4 do
      {:ok, pub} = BrdcNode.Keygen.load_public(Path.join(dir, "v#{i}.pub"))
      assert Enum.at(dn.genesis.validators, i - 1) == pub
    end

    # pedir outro número depois não muda a rede (outro número é outra rede)
    {:ok, again} = Devnet.ensure(dir, validators: 2)
    assert again.genesis == dn.genesis
    assert map_size(again.seeds) == 8
  end

  test "padrão continua sendo 1 validador (o nó embutido do phx.server)", %{tmp_dir: dir} do
    {:ok, dn} = Devnet.ensure(dir)
    assert length(dn.genesis.validators) == 1
    assert Devnet.existing_validators(dir) == 1
  end
end
