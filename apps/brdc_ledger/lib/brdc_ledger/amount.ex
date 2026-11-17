defmodule BrdcLedger.Amount do
  @moduledoc """
  Valores da BRDC: texto pt-BR para a tela e leitura do que a pessoa digita. 1 BRDC = 1.000.000 unidades mínimas (ADR-0010).

  A tela mostra 2 casas decimais e **trunca** (nunca arredonda para cima: não mostramos mais do que
  a pessoa tem). Os 6 casas completas aparecem nos detalhes (`full/1`).
  """

  @unit 1_000_000

  @doc "Parte inteira (com ponto de milhar) e centavos, como `{12.480, 57}` (em texto)."
  @spec split(non_neg_integer()) :: {String.t(), String.t()}
  def split(units) when is_integer(units) and units >= 0 do
    whole = div(units, @unit)

    cents =
      units |> rem(@unit) |> div(10_000) |> Integer.to_string() |> String.pad_leading(2, "0")

    {thousands(whole), cents}
  end

  @doc "Valor em texto: `12.480,57`."
  @spec brdc(non_neg_integer()) :: String.t()
  def brdc(units) do
    {whole, cents} = split(units)
    whole <> "," <> cents
  end

  @doc "Valor com as 6 casas: `12.480,570000`."
  @spec full(non_neg_integer()) :: String.t()
  def full(units) when is_integer(units) and units >= 0 do
    frac = units |> rem(@unit) |> Integer.to_string() |> String.pad_leading(6, "0")
    thousands(div(units, @unit)) <> "," <> frac
  end

  @doc """
  Texto digitado (`"12,5"`) para unidades mínimas; `:error` se inválido ou com mais de 6 casas.

  O ponto só vale como **separador de milhar** bem posicionado (`"1.234,56"`). Um ponto fora de lugar
  (`"1.5"`, que alguém acostumado ao inglês leria como um e meio) é **recusado**, em vez de virar 15 BRDC.
  """
  @spec parse(String.t()) :: {:ok, non_neg_integer()} | :error
  def parse(text) when is_binary(text) do
    case text |> String.trim() |> String.split(",") do
      [whole] -> to_units(whole, "")
      [whole, frac] -> to_units(whole, frac)
      _ -> :error
    end
  end

  # `whole`: dígitos, ou grupos de 3 separados por ponto (milhar) depois de 1 a 3 dígitos
  @whole ~r/\A(\d+|\d{1,3}(\.\d{3})+)\z/

  defp to_units(whole, frac) do
    with true <- whole =~ @whole and (frac == "" or frac =~ ~r/\A\d{1,6}\z/),
         digits = String.replace(whole, ".", ""),
         units =
           String.to_integer(digits) * @unit +
             String.to_integer(String.pad_trailing(frac, 6, "0")),
         true <- units <= 0xFFFFFFFFFFFFFFFF do
      {:ok, units}
    else
      _ -> :error
    end
  end

  defp thousands(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1.")
    |> String.reverse()
  end
end
