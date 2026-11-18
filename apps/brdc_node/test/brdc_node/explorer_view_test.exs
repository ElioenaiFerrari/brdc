defmodule BrdcNode.ExplorerViewTest do
  use ExUnit.Case, async: true
  alias BrdcLedger.Tx
  alias BrdcNode.Explorer

  test "todo tipo de transação (1 a 21) tem nome em português e tipo desconhecido não quebra" do
    for k <- 1..21, do: assert(Explorer.kind_label(k) =~ ~r/\S/)
    assert Explorer.kind_label(9) == "Bem: oferta cancelada"
    assert Explorer.kind_label(10) == "Bem: veto do órgão"
    assert Explorer.kind_label(99) == "Tipo 99"
  end

  test "hash e endereço são encurtados, mas inteiros quando pedido" do
    bin = :crypto.hash(:sha256, "x")
    full = Base.encode16(bin, case: :lower)
    assert Explorer.hex(bin, full: true) == full
    assert Explorer.hex(bin) =~ ~r/^[0-9a-f]{8}…[0-9a-f]{6}$/
    addr = "brdc1" <> String.duplicate("q", 58)
    assert Explorer.short_address(addr) =~ ~r/^brdc1qqqqq….{6}$/
    assert Explorer.short_address(addr, full: true) == addr
  end

  test "dinheiro: sem perder precisão, com ao menos 2 casas" do
    assert Explorer.money(0) == "0,00"
    assert Explorer.money(5_000_000) == "5,00"
    assert Explorer.money(1_234_500_000) == "1.234,50"
    assert Explorer.money(1_172) == "0,001172"
    assert Explorer.money(1_500_000) == "1,50"
    assert Explorer.money(1) == "0,000001"
  end

  test "hora: zero vira traço e o instante sai em UTC" do
    assert Explorer.time(0) == "—"
    assert Explorer.time(0 + 86_400) == "1970-01-02 00:00:00 UTC"
  end

  test "describe: transferência, mint, burn e atestado mostram conta e valor; o resto fica vazio" do
    to = :crypto.hash(:sha256, "to")

    t = %Tx{
      chain_id: "c",
      kind: 1,
      nonce: 0,
      fee: 0,
      sender_pub: <<0::256>>,
      payload: Tx.transfer_payload(to, 1_500_000)
    }

    assert %{to: ^to, amount: 1_500_000} = Explorer.describe(t)

    m = %{t | kind: 2, payload: Tx.issuance_payload(to, 7, "ref", [])}
    assert %{to: ^to, amount: 7, ref: "ref", approvals: 0} = Explorer.describe(m)

    a = %{t | kind: 4, payload: Tx.attestation_payload(3, 900, "banco", [])}
    assert %{seq: 3, reserve: 900, ref: "banco"} = Explorer.describe(a)

    assert Explorer.describe(%{t | kind: 20}) == %{}
    assert Explorer.describe(%{t | payload: <<1, 2>>}) == %{}
  end
end
