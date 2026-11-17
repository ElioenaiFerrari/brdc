defmodule BrdcNode.BlockStoreTest do
  use ExUnit.Case, async: true
  alias BrdcNode.BlockStore.File, as: LogFile

  @moduletag :tmp_dir

  defp path(dir), do: Path.join(dir, "blocks.log")

  defp write_all(dir, records) do
    {:ok, s, [], _} = LogFile.open(path(dir))
    for r <- records, do: :ok = LogFile.append(s, r)
    LogFile.close(s)
  end

  test "abrir um arquivo novo devolve vazio; o que foi gravado volta na ordem", %{tmp_dir: dir} do
    assert {:ok, s, [], %{truncated_bytes: 0}} = LogFile.open(path(dir))
    LogFile.close(s)
    write_all(dir, ["um", "dois", String.duplicate("x", 5000)])
    assert {:ok, s, ["um", "dois", big], %{truncated_bytes: 0}} = LogFile.open(path(dir))
    assert byte_size(big) == 5000
    LogFile.close(s)
  end

  test "continua gravando depois de reabrir (sem sobrescrever)", %{tmp_dir: dir} do
    write_all(dir, ["a", "b"])
    {:ok, s, ["a", "b"], _} = LogFile.open(path(dir))
    :ok = LogFile.append(s, "c")
    LogFile.close(s)
    {:ok, s, ["a", "b", "c"], _} = LogFile.open(path(dir))
    LogFile.close(s)
  end

  test "cauda truncada em qualquer ponto: descarta só o registro incompleto e o arquivo fica são",
       %{tmp_dir: dir} do
    write_all(dir, ["primeiro", "segundo", "terceiro"])
    full = File.read!(path(dir))
    last_start = byte_size(full) - (20 + byte_size("terceiro"))

    # corta em cada byte dentro do último registro (cabeçalho e conteúdo)
    for cut <- last_start..(byte_size(full) - 1) do
      File.write!(path(dir), binary_part(full, 0, cut))
      assert {:ok, s, ["primeiro", "segundo"], %{truncated_bytes: lost}} = LogFile.open(path(dir))
      assert lost == cut - last_start
      # o arquivo foi truncado e aceita novas gravações
      :ok = LogFile.append(s, "novo")
      LogFile.close(s)

      assert {:ok, s, ["primeiro", "segundo", "novo"], %{truncated_bytes: 0}} =
               LogFile.open(path(dir))

      LogFile.close(s)
    end
  end

  test "escrita rasgada (soma errada no ÚLTIMO registro) é descartada", %{tmp_dir: dir} do
    write_all(dir, ["bom", "rasgado"])
    full = File.read!(path(dir))
    n = byte_size(full)

    File.write!(
      path(dir),
      binary_part(full, 0, n - 1) <> <<:erlang.bxor(:binary.last(full), 0xFF)>>
    )

    assert {:ok, s, ["bom"], %{truncated_bytes: lost}} = LogFile.open(path(dir))
    assert lost == 20 + byte_size("rasgado")
    LogFile.close(s)
  end

  test "corrupção no MEIO é erro fatal e o arquivo não é tocado", %{tmp_dir: dir} do
    write_all(dir, ["um", "dois", "tres"])
    full = File.read!(path(dir))
    # troca um byte do conteúdo do segundo registro
    pos = 20 + byte_size("um") + 20
    <<head::binary-size(^pos), b, rest::binary>> = full
    File.write!(path(dir), head <> <<:erlang.bxor(b, 1)>> <> rest)
    before = File.read!(path(dir))
    assert {:error, {:corrupt, 1}} = LogFile.open(path(dir))
    assert File.read!(path(dir)) == before
  end

  test "tamanho absurdo no meio também é corrupção; registro grande demais não é aceito", %{
    tmp_dir: dir
  } do
    write_all(dir, ["um", "dois"])
    full = File.read!(path(dir))
    <<_size::32, rest::binary>> = full
    File.write!(path(dir), <<0xFFFFFFFF::32>> <> rest)
    assert {:error, {:corrupt, 0}} = LogFile.open(path(dir))

    File.rm!(path(dir))
    {:ok, s, [], _} = LogFile.open(path(dir))

    assert {:error, :record_too_big} =
             LogFile.append(s, :binary.copy(<<0>>, 16 * 1024 * 1024 + 1))

    LogFile.close(s)
  end
end
