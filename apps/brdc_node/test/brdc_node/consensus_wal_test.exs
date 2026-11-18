defmodule BrdcNode.ConsensusWalTest do
  use ExUnit.Case, async: true
  alias BrdcConsensus.{Engine, Proposal, Vote}
  alias BrdcCrypto.{Ed25519, Hash}
  alias BrdcNode.ConsensusWal, as: Wal

  @moduletag :tmp_dir
  @chain "wal-test"

  defp seeds, do: for(i <- 0..3, do: :crypto.hash(:sha256, "wal-validator-#{i}"))
  defp pubs, do: Enum.map(seeds(), &Ed25519.public_key/1)
  defp enc, do: fn b -> b end
  defp dec, do: fn bin -> {:ok, bin} end
  defp hash_fn, do: fn block -> Hash.tagged("brdc/wal/block", block) end

  defp engine(i, height \\ 1) do
    Engine.new(
      chain_id: @chain,
      height: height,
      validators: pubs(),
      seed: Enum.at(seeds(), i),
      hash_fn: hash_fn(),
      valid_fn: fn _ -> true end
    )
  end

  defp proposal(i, r, block, height \\ 1),
    do: Proposal.sign(@chain, height, r, -1, block, hash_fn().(block), Enum.at(seeds(), i))

  defp vote(i, type, r, block, height \\ 1),
    do: Vote.sign(@chain, type, height, r, block && hash_fn().(block), Enum.at(seeds(), i))

  defp open(dir, height, i) do
    Wal.open(Path.join(dir, "consensus.wal"), height, Enum.at(pubs(), i), enc(), dec())
  end

  test "grava só as mensagens PRÓPRIAS, na ordem; ações que não são transmissões são ignoradas",
       %{tmp_dir: dir} do
    {:ok, wal, []} = open(dir, 1, 2)
    mine1 = vote(2, :prevote, 0, "b")
    mine2 = proposal(2, 1, "c")
    others = vote(0, :prevote, 0, "b")

    actions = [
      {:schedule_timeout, :prevote, 0},
      {:broadcast, mine1},
      {:broadcast, others},
      {:need_block, 3},
      {:broadcast, mine2}
    ]

    assert :ok = Wal.persist_own(wal, actions)
    Wal.close(wal)

    assert {:ok, wal, [^mine1, ^mine2]} = open(dir, 1, 2)
    Wal.close(wal)
  end

  test "ida e volta com o motor: o diário devolve o que o motor precisa para retomar", %{
    tmp_dir: dir
  } do
    {:ok, wal, []} = open(dir, 1, 2)
    {e, a1} = Engine.start(engine(2))
    {e, a2} = Engine.handle(e, {:proposal, proposal(1, 0, "bloco-b")})
    assert :ok = Wal.persist_own(wal, a1 ++ a2)
    assert e.step == :prevote
    Wal.close(wal)

    {:ok, wal, journal} = open(dir, 1, 2)
    {restored, _} = Engine.restore(engine(2), journal)
    assert {restored.round, restored.step} == {0, :prevote}
    Wal.close(wal)
  end

  test "cauda rasgada (a mensagem nunca saiu) é descartada; o resto fica", %{tmp_dir: dir} do
    {:ok, wal, []} = open(dir, 1, 2)

    :ok =
      Wal.persist_own(wal, [
        {:broadcast, vote(2, :prevote, 0, "b")},
        {:broadcast, vote(2, :precommit, 0, "b")}
      ])

    Wal.close(wal)
    path = Path.join(dir, "consensus.wal")
    full = File.read!(path)
    File.write!(path, binary_part(full, 0, byte_size(full) - 9))

    assert {:ok, wal, [%Vote{type: :prevote}]} = open(dir, 1, 2)
    Wal.close(wal)
  end

  test "registro ilegível (soma válida, conteúdo lixo) é fatal: sem diário íntegro o validador não vota",
       %{tmp_dir: dir} do
    alias BrdcNode.BlockStore.File, as: LogFile
    path = Path.join(dir, "consensus.wal")
    {:ok, s, [], _} = LogFile.open(path)
    :ok = LogFile.append(s, <<1, "isto não é um voto">>)
    LogFile.close(s)
    assert {:error, {:bad_wal, 0}} = open(dir, 1, 2)

    File.rm!(path)
    {:ok, s, [], _} = LogFile.open(path)
    :ok = LogFile.append(s, <<9, "tipo desconhecido">>)
    LogFile.close(s)
    assert {:error, {:bad_wal, 0}} = open(dir, 1, 2)
  end

  test "abrir numa altura nova descarta o diário da altura antiga (e mantém só a atual)", %{
    tmp_dir: dir
  } do
    {:ok, wal, []} = open(dir, 1, 2)
    :ok = Wal.persist_own(wal, [{:broadcast, vote(2, :prevote, 0, "b", 1)}])
    Wal.close(wal)

    {:ok, wal, []} = open(dir, 2, 2)
    :ok = Wal.persist_own(wal, [{:broadcast, vote(2, :prevote, 0, "x", 2)}])
    Wal.close(wal)

    {:ok, wal, [%Vote{height: 2}]} = open(dir, 2, 2)
    Wal.close(wal)
    # o arquivo em disco já não tem a altura 1
    {:ok, wal, []} = open(dir, 1, 2)
    Wal.close(wal)
  end

  test "advance esvazia o diário (altura decidida) e continua gravável", %{tmp_dir: dir} do
    {:ok, wal, []} = open(dir, 1, 2)
    :ok = Wal.persist_own(wal, [{:broadcast, vote(2, :prevote, 0, "b")}])
    {:ok, wal} = Wal.advance(wal)
    :ok = Wal.persist_own(wal, [{:broadcast, vote(2, :prevote, 0, "novo", 2)}])
    Wal.close(wal)
    assert {:ok, wal, [%Vote{height: 2}]} = open(dir, 2, 2)
    Wal.close(wal)
  end

  test "falha ao gravar: persist_own devolve erro (e o chamador NÃO pode transmitir)", %{
    tmp_dir: dir
  } do
    {:ok, wal, []} = open(dir, 1, 2)
    Wal.close(wal)
    # arquivo fechado: a gravação falha
    assert {:error, _} = Wal.persist_own(wal, [{:broadcast, vote(2, :prevote, 0, "b")}])
  end
end
