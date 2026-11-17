defmodule BrdcNode.Client do
  @moduledoc """
  Cliente da porta pública de um nó (usado pela carteira web e pelas ferramentas). **Não confia no nó**:
  por ora só lê estado e envia transações já assinadas; as provas (certificado de commit, raiz de estado)
  chegam quando o nó tiver mais de um validador.
  """
  alias BrdcCrypto.Encoding
  alias BrdcNode.Handler
  alias BrdcP2p.PublicPort

  @type endpoint :: {charlist() | :inet.ip_address(), :inet.port_number()}

  @spec status(endpoint()) :: {:ok, map()} | {:error, term()}
  def status({host, port}) do
    with {:ok, bin} <- PublicPort.request(host, port, :status, <<>>),
         {:ok, [chain, height, time, supply, last, pending, base, per_byte, contract_fee]} <-
           Encoding.decode(Handler.status_schema(), bin) do
      {:ok,
       %{
         chain_id: chain,
         height: height,
         time: time,
         supply: supply,
         last_hash: if(last == <<>>, do: nil, else: last),
         pending: pending,
         transfer_base: base,
         per_byte: per_byte,
         contract_fee: contract_fee
       }}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @spec account(endpoint(), <<_::256>>) :: {:ok, map()} | {:error, term()}
  def account({host, port}, <<_::256>> = addr) do
    with {:ok, bin} <- PublicPort.request(host, port, :get_account, addr),
         {:ok, [balance, nonce, pbalance, pnonce]} <-
           Encoding.decode(Handler.account_schema(), bin) do
      {:ok, %{balance: balance, nonce: nonce, pending_balance: pbalance, pending_nonce: pnonce}}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @doc "Contratos entre partes de um endereço (estado confirmado)."
  @spec contracts_of(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def contracts_of({host, port}, <<_::256>> = addr) do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<1, addr::binary>>),
         {:ok, [entries]} <- Encoding.decode([{:list, :bytes}], bin),
         {:ok, list} <- decode_contracts(entries) do
      {:ok, list}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  defp decode_contracts(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn bin, {:ok, acc} ->
      case decode_contract(bin) do
        {:ok, c} -> {:cont, {:ok, [c | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      :error -> {:error, :bad_response}
    end
  end

  defp decode_contract(bin) do
    with {:ok, [id, template, a, b, state, escrow, terms, vars]} <-
           Encoding.decode(Handler.contract_schema(), bin),
         {:ok, terms} <- decode_kv(terms),
         {:ok, vars} <- decode_kv(vars) do
      {:ok,
       %{
         id: id,
         template: template,
         a: a,
         b: b,
         state: state,
         escrow: escrow,
         terms: terms,
         vars: vars
       }}
    else
      _ -> :error
    end
  end

  defp decode_kv(list) do
    Enum.reduce_while(list, {:ok, %{}}, fn bin, {:ok, acc} ->
      case Encoding.decode(Handler.kv_schema(), bin) do
        {:ok, [k, v]} -> {:cont, {:ok, Map.put(acc, k, v)}}
        _ -> {:halt, :error}
      end
    end)
  end

  @spec submit_tx(endpoint(), binary()) :: {:ok, <<_::256>>} | {:error, term()}
  def submit_tx({host, port}, tx_bin) when is_binary(tx_bin) do
    case PublicPort.request(host, port, :submit_tx, tx_bin) do
      {:ok, <<_::256>> = id} -> {:ok, id}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} when is_binary(reason) -> {:error, String.to_atom(reason)}
      {:error, _} = err -> err
    end
  end
end
