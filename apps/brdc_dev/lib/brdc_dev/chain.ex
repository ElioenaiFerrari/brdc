defmodule BrdcDev.Chain do
  @moduledoc """
  Envia transações de TESTE assinadas por uma conta (carteira de teste ou emissor) e espera entrarem num bloco.
  Só desenvolvimento. Fala com um nó pela porta pública, como a carteira.
  """
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcLedger.{Executor, Params, Tx}
  alias BrdcNode.Client

  @type endpoint :: {charlist(), pos_integer()}

  @doc """
  Assina e envia uma transação de `seed` com o `payload` do tipo `kind`. `fee: :min` calcula a taxa mínima das
  transferências a partir do estado do nó; um número usa esse valor. Devolve o id e o nonce usado.
  """
  @spec send_tx(endpoint(), <<_::256>>, pos_integer(), binary(), :min | non_neg_integer()) ::
          {:ok, %{id: <<_::256>>, nonce: non_neg_integer()}} | {:error, term()}
  def send_tx(endpoint, seed, kind, payload, fee \\ 0) do
    pub = Ed25519.public_key(seed)

    with {:ok, status} <- Client.status(endpoint),
         {:ok, acc} <- Client.account(endpoint, Address.hash(pub)) do
      tx = %Tx{
        chain_id: status.chain_id,
        kind: kind,
        nonce: acc.pending_nonce,
        fee: 0,
        sender_pub: pub,
        payload: payload
      }

      tx = %{tx | fee: resolve_fee(fee, status, tx)} |> Tx.sign(seed)

      with {:ok, id} <- Client.submit_tx(endpoint, Tx.encode(tx)),
           do: {:ok, %{id: id, nonce: acc.pending_nonce}}
    end
  end

  defp resolve_fee(:min, status, tx) do
    params = struct(Params, transfer_base: status.transfer_base, per_byte: status.per_byte)
    Executor.min_fee(params, tx)
  end

  defp resolve_fee(fee, _status, _tx), do: fee

  @doc "Espera o nonce confirmado de `address_hash` passar de `nonce` (a transação entrou num bloco)."
  @spec await_included(endpoint(), <<_::256>>, non_neg_integer(), non_neg_integer()) ::
          :ok | {:error, :timeout}
  def await_included(endpoint, address_hash, nonce, timeout_ms \\ 30_000) do
    if BrdcDev.Net.wait_until(
         fn -> confirmed_nonce(endpoint, address_hash) > nonce end,
         timeout_ms
       ),
       do: :ok,
       else: {:error, :timeout}
  end

  defp confirmed_nonce(endpoint, hash) do
    case Client.account(endpoint, hash) do
      {:ok, acc} -> acc.nonce
      _ -> -1
    end
  end

  @doc "Saldo confirmado (em unidades) de um endereço."
  @spec balance(endpoint(), <<_::256>>) :: {:ok, non_neg_integer()} | {:error, term()}
  def balance(endpoint, hash) do
    with {:ok, acc} <- Client.account(endpoint, hash), do: {:ok, acc.balance}
  end
end
