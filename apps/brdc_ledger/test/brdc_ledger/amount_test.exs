defmodule BrdcLedger.AmountTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias BrdcLedger.Amount, as: Format

  test "mostra 2 casas e trunca (nunca arredonda para cima)" do
    assert Format.brdc(0) == "0,00"
    assert Format.brdc(1) == "0,00"
    assert Format.brdc(999_999) == "0,99"
    assert Format.brdc(1_000_000) == "1,00"
    assert Format.brdc(12_480_570_000) == "12.480,57"
    assert Format.brdc(1_234_567_890_000_000) == "1.234.567.890,00"
    assert Format.split(5_000_000) == {"5", "00"}
  end

  test "as 6 casas completas" do
    assert Format.full(1) == "0,000001"
    assert Format.full(12_480_570_000) == "12.480,570000"
  end

  test "entrada digitada: vírgula decimal, ponto de milhar, no máximo 6 casas" do
    assert Format.parse("12,5") == {:ok, 12_500_000}
    assert Format.parse("1.234,56") == {:ok, 1_234_560_000}
    assert Format.parse("0,000001") == {:ok, 1}
    assert Format.parse("7") == {:ok, 7_000_000}

    for bad <- ["", ",", "abc", "1,2,3", "1,1234567", "-1", "1,5x"],
        do: assert(Format.parse(bad) == :error)

    # o ponto só é milhar bem posicionado: "1.5" NÃO pode virar 15 BRDC
    assert Format.parse("1.234.567,5") == {:ok, 1_234_567_500_000}

    for bad <- ["1.5", "12.34", "1.23", "1..234", ".5", "1.2345", "12.345.6"] do
      assert Format.parse(bad) == :error, bad
    end

    assert Format.parse("99999999999999999999999") == :error
  end

  property "ida e volta com as 6 casas" do
    check all(units <- integer(0..0xFFFFFFFFFFFFFFFF)) do
      assert {:ok, ^units} = Format.parse(Format.full(units))
    end
  end

  property "a tela nunca mostra mais do que o saldo" do
    check all(units <- integer(0..0xFFFFFFFFFFFFFFFF)) do
      {:ok, shown} = Format.parse(Format.brdc(units))
      assert shown <= units
    end
  end
end
