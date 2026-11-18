defmodule BrdcNode.Explorer do
  @moduledoc """
  Apresentação comum do explorador (terminal e web): o nome, em português, de cada tipo de transação, e
  encurtadores de hash e endereço. **Puro**: não consulta ninguém.
  """

  # conferido contra `Assets.run/4`, `Credentials.run/4` e `Contracts.run/4`
  @kinds %{
    1 => "Transferência",
    2 => "Emissão (mint)",
    3 => "Resgate (burn)",
    4 => "Atestado de reserva",
    5 => "Bem: classe criada",
    6 => "Bem: registro",
    7 => "Bem: oferta",
    8 => "Bem: aceite do comprador",
    9 => "Bem: oferta cancelada",
    10 => "Bem: veto do órgão",
    11 => "Bem: negociação finalizada",
    12 => "Bem: gravame",
    13 => "Bem: gravame removido",
    14 => "Credencial: tipo criado",
    15 => "Credencial: emissão",
    16 => "Credencial: contestação",
    17 => "Credencial: veto do órgão",
    18 => "Credencial: ativação",
    19 => "Credencial: revogação",
    20 => "Contrato: criado",
    21 => "Contrato: ação"
  }

  @doc "Nome do tipo (`kind`) da transação."
  @spec kind_label(non_neg_integer()) :: String.t()
  def kind_label(kind), do: Map.get(@kinds, kind, "Tipo #{kind}")

  @doc """
  O que a transação move, para mostrar: transferência, mint e burn trazem a conta e o valor; o atestado, a reserva.
  Os demais tipos devolvem `%{}` (só o tipo e o remetente aparecem). Payload que não decodifica também dá `%{}`.
  """
  @spec describe(BrdcLedger.Tx.t()) :: map()
  def describe(%BrdcLedger.Tx{kind: 1, payload: p}) do
    case BrdcCrypto.Encoding.decode([{:fixed, 32}, :u64], p) do
      {:ok, [to, amount]} -> %{to: to, amount: amount}
      _ -> %{}
    end
  end

  def describe(%BrdcLedger.Tx{kind: kind, payload: p}) when kind in [2, 3] do
    case BrdcCrypto.Encoding.decode([{:fixed, 32}, :u64, :string, {:list, :bytes}], p) do
      {:ok, [account, amount, ref, approvals]} ->
        %{to: account, amount: amount, ref: ref, approvals: length(approvals)}

      _ ->
        %{}
    end
  end

  def describe(%BrdcLedger.Tx{kind: 4, payload: p}) do
    case BrdcCrypto.Encoding.decode([:u64, :u64, :string, {:list, :bytes}], p) do
      {:ok, [seq, reserve, ref, approvals]} ->
        %{seq: seq, reserve: reserve, ref: ref, approvals: length(approvals)}

      _ ->
        %{}
    end
  end

  def describe(_), do: %{}

  @doc """
  Valor em BRDC **sem perder precisão**: até 6 casas, tirando zeros finais mas mantendo ao menos 2
  (`5,00`, `1.234,50`, `0,001172`). `Amount.brdc/1` arredonda para 2 casas e esconderia taxas pequenas.
  """
  @spec money(non_neg_integer()) :: String.t()
  def money(units) when is_integer(units) and units >= 0 do
    case String.split(BrdcLedger.Amount.full(units), ",") do
      [int, dec] ->
        int <> "," <> (dec |> String.trim_trailing("0") |> String.pad_trailing(2, "0"))

      _ ->
        BrdcLedger.Amount.full(units)
    end
  end

  @doc "Hash em hexadecimal, inteiro (`full: true`) ou encurtado (`ab12cd34…ef56`)."
  @spec hex(binary(), keyword()) :: String.t()
  def hex(bin, opts \\ []) when is_binary(bin) do
    full = Base.encode16(bin, case: :lower)

    if opts[:full] || byte_size(full) <= 16,
      do: full,
      else: String.slice(full, 0, 8) <> "…" <> String.slice(full, -6, 6)
  end

  @doc "Endereço `brdc1…` encurtado (`brdc1abcd…wxyz`) ou inteiro com `full: true`."
  @spec short_address(String.t(), keyword()) :: String.t()
  def short_address(addr, opts \\ []) when is_binary(addr) do
    if opts[:full] || String.length(addr) <= 20,
      do: addr,
      else: String.slice(addr, 0, 10) <> "…" <> String.slice(addr, -6, 6)
  end

  @doc "Hora em `AAAA-MM-DD HH:MM:SS` (UTC) de um instante em segundos Unix; `0` vira `—`."
  @spec time(non_neg_integer()) :: String.t()
  def time(0), do: "—"

  def time(sec) when is_integer(sec) and sec > 0 do
    case DateTime.from_unix(sec) do
      {:ok, dt} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S") <> " UTC"
      _ -> "—"
    end
  end
end
