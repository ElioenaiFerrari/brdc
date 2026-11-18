defmodule BrdcConsensus.ProposeTimeoutTest do
  # O prazo da proposta vale para TODOS os validadores, inclusive o proponente. Antes, o proponente sem nada para
  # propor (mempool vazio, não há bloco vazio) esperava uma transação para sempre e a rodada nunca andava.
  use ExUnit.Case, async: true
  alias BrdcConsensus.Engine
  alias BrdcCrypto.{Ed25519, Hash}

  @chain "sim"

  defp seeds, do: for(i <- 0..3, do: :crypto.hash(:sha256, "sim-validator-#{i}"))
  defp pubs, do: Enum.map(seeds(), &Ed25519.public_key/1)

  defp engine(i) do
    Engine.new(
      chain_id: @chain,
      height: 1,
      validators: pubs(),
      seed: Enum.at(seeds(), i),
      hash_fn: fn block -> Hash.tagged("brdc/sim/block", inspect(block)) end,
      valid_fn: fn _ -> true end
    )
  end

  # a altura 1, rodada 0, é proposta pelo validador de índice 1 (rem(h + r, n))
  defp proposer_index, do: Enum.find_index(pubs(), &(&1 == Engine.proposer(engine(0), 0)))

  defp prevotes(actions), do: for({:broadcast, %{type: :prevote} = v} <- actions, do: v)

  test "o proponente sem bloco pede o bloco E agenda o prazo da proposta" do
    {_e, actions} = Engine.start(engine(proposer_index()))
    assert {:need_block, 0} in actions
    assert {:schedule_timeout, :propose, 0} in actions
  end

  test "quando o prazo vence sem bloco, o proponente vota NULO e passa ao prevote (a rodada anda)" do
    i = proposer_index()
    {e, _} = Engine.start(engine(i))
    {e, actions} = Engine.handle(e, {:timeout, :propose, 0})

    assert e.step == :prevote
    assert [%{block_hash: nil, round: 0}] = prevotes(actions)
  end

  test "quem não é proponente continua agendando o prazo" do
    other = Enum.find(0..3, &(&1 != proposer_index()))
    {_e, actions} = Engine.start(engine(other))
    assert {:schedule_timeout, :propose, 0} in actions
    refute Enum.any?(actions, &match?({:need_block, _}, &1))
  end

  test "o proponente que propõe a tempo NÃO vota nulo quando o prazo vence depois" do
    i = proposer_index()
    {e, _} = Engine.start(engine(i))
    {e, actions} = Engine.handle(e, {:block, {:txs, 1}})
    # propôs e votou no próprio bloco (prevote com hash)
    assert [%{block_hash: hash}] = prevotes(actions)
    assert hash != nil

    {e2, actions2} = Engine.handle(e, {:timeout, :propose, 0})
    assert e2.step == e.step
    assert prevotes(actions2) == []
  end

  test "o prazo de uma rodada antiga não mexe na rodada atual" do
    other = Enum.find(0..3, &(&1 != proposer_index()))
    {e, _} = Engine.start(engine(other))
    {e2, actions} = Engine.handle(e, {:timeout, :propose, 7})
    assert e2.step == :propose and actions == []
  end
end
