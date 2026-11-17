defmodule BrdcCryptoTest do
  use ExUnit.Case, async: true

  test "o app existe e está documentado" do
    assert Code.ensure_loaded?(BrdcCrypto)
    assert {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(BrdcCrypto)
    assert doc =~ "Fase"
  end
end
