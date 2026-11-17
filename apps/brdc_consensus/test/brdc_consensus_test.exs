defmodule BrdcConsensusTest do
  use ExUnit.Case, async: true

  test "o app existe e está documentado" do
    assert Code.ensure_loaded?(BrdcConsensus)
    assert {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(BrdcConsensus)
    assert doc =~ "Fase"
  end
end
