defmodule BrdcDev.ResetTest do
  # a tarefa `brdc.devnet.reset` age só dentro da pasta temporária do teste
  use ExUnit.Case, async: false
  alias BrdcDev.Net
  alias Mix.Tasks.Brdc.Devnet.Reset

  @moduletag :tmp_dir

  defp free_port do
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    :gen_tcp.close(l)
    port
  end

  # rede de mentira: configuração, gênese, uma chave e, por validador, dados, pid e log
  defp fake_network(dir, n) do
    cfg = %{validators: n, public_base: free_port(), peer_base: free_port()}
    Net.write_config(dir, cfg)
    File.write!(Path.join(dir, "genesis.json"), "{}")
    File.write!(Path.join(dir, "v1.seed"), "chave")

    for i <- 1..n do
      File.mkdir_p!(Net.data_dir(dir, i))
      File.write!(Path.join(Net.data_dir(dir, i), "blocks.log"), "x")
      File.write!(Net.log_path(dir, i), "log")
    end

    File.mkdir_p!(Path.join(dir, "data"))
    cfg
  end

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "reset apaga blocos, logs e a pasta data; mantém chaves, gênese e configuração", %{
    tmp_dir: dir
  } do
    fake_network(dir, 2)
    Reset.run(["--dir", dir])

    for i <- 1..2 do
      refute File.exists?(Net.data_dir(dir, i))
      refute File.exists?(Net.log_path(dir, i))
    end

    refute File.exists?(Path.join(dir, "data"))
    assert File.exists?(Path.join(dir, "v1.seed"))
    assert File.exists?(Path.join(dir, "genesis.json"))
    assert Net.read_config(dir) != nil
    assert_received {:mix_shell, :info, [msg]} when is_binary(msg)
    assert msg =~ "apagado"
  end

  test "reset --all apaga também a gênese e a configuração, mas nunca as chaves", %{tmp_dir: dir} do
    fake_network(dir, 2)
    Reset.run(["--all", "--dir", dir])
    refute File.exists?(Path.join(dir, "genesis.json"))
    refute File.exists?(Net.config_path(dir))
    assert File.exists?(Path.join(dir, "v1.seed"))
  end

  test "sem nada a apagar, avisa e não falha", %{tmp_dir: dir} do
    Reset.run(["--dir", dir, "--port", Integer.to_string(free_port())])
    assert_received {:mix_shell, :info, ["nada a apagar em " <> _]}
  end

  test "recusa se há validador rodando (pid vivo) e não apaga nada", %{tmp_dir: dir} do
    fake_network(dir, 2)
    File.write!(Net.pid_path(dir, 1), System.pid() <> "\n")

    assert_raise Mix.Error, ~r/rodando \(1\)/, fn -> Reset.run(["--dir", dir]) end
    assert File.exists?(Net.data_dir(dir, 1))
    assert File.exists?(Net.data_dir(dir, 2))
  end

  test "recusa se há um nó respondendo na porta e não apaga nada", %{tmp_dir: dir} do
    fake_network(dir, 1)
    {:ok, l} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(l)
    on_exit(fn -> :gen_tcp.close(l) end)

    assert_raise Mix.Error, ~r/respondendo na porta/, fn ->
      Reset.run(["--dir", dir, "--port", Integer.to_string(port)])
    end

    assert File.exists?(Net.data_dir(dir, 1))
  end

  test "--help só mostra a ajuda: não apaga nada", %{tmp_dir: dir} do
    fake_network(dir, 1)
    assert catch_exit(Reset.run(["--help", "--dir", dir])) == :normal
    assert File.exists?(Net.data_dir(dir, 1))
  end
end
