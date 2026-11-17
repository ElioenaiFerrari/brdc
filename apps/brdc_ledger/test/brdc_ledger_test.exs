defmodule BrdcLedgerTest do
  use ExUnit.Case, async: true

  test "o app existe e está documentado" do
    assert Code.ensure_loaded?(BrdcLedger)
    assert {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(BrdcLedger)
    assert doc =~ "Fase"
  end
end
