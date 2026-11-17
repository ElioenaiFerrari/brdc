defmodule BrdcCrypto.HashVectorsTest do
  @moduledoc """
  Lê vectors/hash.json (gerado por `mix run tools/gen_wallet_vectors.exs`), o MESMO arquivo que o JS da
  carteira confere. Se o Elixir mudar, este teste acusa; se o JS divergir, o teste do JS acusa.
  """
  use ExUnit.Case, async: true
  alias BrdcCrypto.Hash

  @path Path.expand("../../../../vectors/hash.json", __DIR__)
  @external_resource @path
  @vectors @path |> File.read!() |> JSON.decode!()

  defp hex(b), do: Base.encode16(b, case: :lower)

  test "SHA3-256 e hash etiquetado batem com o vetor (todos os tamanhos, inclusive bordas de bloco)" do
    assert length(@vectors["cases"]) > 100

    for c <- @vectors["cases"] do
      input = Base.decode16!(c["input"], case: :lower)
      assert byte_size(input) == c["len"]
      assert hex(Hash.sha3(input)) == c["sha3_256"], "sha3 len=#{c["len"]}"
      assert hex(Hash.tagged(@vectors["tag"], input)) == c["tagged"], "tagged len=#{c["len"]}"
    end
  end
end
