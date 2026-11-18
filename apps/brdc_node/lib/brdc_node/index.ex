defmodule BrdcNode.Index do
  @moduledoc """
  Índice de transações do nó (explorador, M4): do id da transação ao bloco e à posição, e, por conta, o histórico
  de transações em que ela aparece. **Puro**: `(índice, bloco) → índice`. É reconstruído do log de blocos ao subir.

  Quem aparece numa transação: o **remetente** sempre; e o **destinatário** nas transferências, o titular nos
  `mint` e `burn`. As demais (bens, credenciais, contratos) indexam só o remetente (limite honesto: um contrato
  não aparece no histórico da contraparte, só na consulta de contratos).

  Memória: um registro por transação e até #{500} entradas por conta (as mais novas): serve ao desenvolvimento e à
  testnet; um índice em disco é trabalho futuro.
  """
  alias BrdcCrypto.Address
  alias BrdcLedger.{Block, Tx}

  @max_per_account 500

  @type entry :: %{
          id: <<_::256>>,
          height: pos_integer(),
          index: non_neg_integer(),
          role: :sender | :receiver
        }
  @type t :: %{
          txs: %{<<_::256>> => {pos_integer(), non_neg_integer()}},
          accounts: %{<<_::256>> => [entry()]}
        }

  @spec new() :: t()
  def new, do: %{txs: %{}, accounts: %{}}

  @doc "Acrescenta um bloco (na ordem das alturas)."
  @spec add_block(t(), Block.t()) :: t()
  def add_block(index, %Block{height: h, txs: txs}) do
    txs
    |> Enum.with_index()
    |> Enum.reduce(index, fn {tx, i}, acc ->
      id = Tx.id(tx)
      acc = %{acc | txs: Map.put(acc.txs, id, {h, i})}

      Enum.reduce(involved(tx), acc, fn {addr, role}, a ->
        entry = %{id: id, height: h, index: i, role: role}

        %{
          a
          | accounts:
              Map.update(a.accounts, addr, [entry], &Enum.take([entry | &1], @max_per_account))
        }
      end)
    end)
  end

  @doc "Onde está a transação: `{altura, posição no bloco}`."
  @spec lookup(t(), <<_::256>>) :: {:ok, {pos_integer(), non_neg_integer()}} | :error
  def lookup(%{txs: txs}, id), do: Map.fetch(txs, id)

  @doc "Histórico da conta, do mais novo ao mais antigo, até `limit`."
  @spec account(t(), <<_::256>>, pos_integer()) :: [entry()]
  def account(%{accounts: accounts}, addr, limit),
    do: accounts |> Map.get(addr, []) |> Enum.take(limit)

  @doc "Endereços que a transação envolve, com o papel de cada um."
  @spec involved(Tx.t()) :: [{<<_::256>>, :sender | :receiver}]
  def involved(%Tx{} = tx) do
    sender = {Address.hash(tx.sender_pub), :sender}

    case destination(tx) do
      nil -> [sender]
      dest when dest == elem(sender, 0) -> [sender]
      dest -> [sender, {dest, :receiver}]
    end
  end

  # transferência (1): [destino, valor]; mint (2) e burn (3): [conta, valor, ref, aprovações]
  defp destination(%Tx{kind: kind, payload: <<dest::binary-size(32), _::binary>>})
       when kind in [1, 2, 3], do: dest

  defp destination(_), do: nil
end
