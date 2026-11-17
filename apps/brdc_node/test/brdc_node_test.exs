defmodule BrdcNodeTest do
  use ExUnit.Case, async: true

  test "o app existe e está documentado" do
    assert Code.ensure_loaded?(BrdcNode)
    assert {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(BrdcNode)
    assert doc =~ "Fase"
  end
end
