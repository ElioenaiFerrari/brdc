defmodule BrdcWebWeb.Wallet.Chain do
  @moduledoc """
  A carteira (servidor) como **cliente** de um nó, pela porta pública em TCP (`BrdcNode.Client`). O
  endereço do nó vem de `config :brdc_web, :node, host: …, port: …`. Não confia no nó: só lê saldo e
  parâmetros e repassa transações **já assinadas no navegador**. Se o nó não responde, a carteira segue
  funcionando e mostra "sem conexão".
  """
  alias BrdcCrypto.{Address, Bech32m}
  alias BrdcNode.Client

  @type snapshot :: %{
          chain_id: String.t(),
          height: non_neg_integer(),
          time: non_neg_integer(),
          contract_fee: non_neg_integer(),
          balance: non_neg_integer(),
          pending_balance: non_neg_integer(),
          nonce: non_neg_integer(),
          pending_nonce: non_neg_integer(),
          transfer_base: non_neg_integer(),
          per_byte: non_neg_integer(),
          pending: non_neg_integer()
        }

  @doc "Endereço do nó configurado, ou `nil`."
  @spec endpoint() :: Client.endpoint() | nil
  def endpoint do
    case Application.get_env(:brdc_web, :node) do
      [host: host, port: port] ->
        {host, port}

      cfg when is_list(cfg) ->
        {Keyword.get(cfg, :host, ~c"127.0.0.1"), Keyword.fetch!(cfg, :port)}

      _ ->
        nil
    end
  end

  @doc "Estado da rede e da conta, ou `{:error, :offline}`."
  @spec snapshot(String.t()) :: {:ok, snapshot()} | {:error, :offline}
  def snapshot(address) do
    with endpoint when endpoint != nil <- endpoint(),
         {:ok, hash} <- Address.decode(address),
         {:ok, st} <- Client.status(endpoint),
         {:ok, acc} <- Client.account(endpoint, hash) do
      {:ok,
       %{
         chain_id: st.chain_id,
         height: st.height,
         time: st.time,
         contract_fee: st.contract_fee,
         pending: st.pending,
         transfer_base: st.transfer_base,
         per_byte: st.per_byte,
         balance: acc.balance,
         pending_balance: acc.pending_balance,
         nonce: acc.nonce,
         pending_nonce: acc.pending_nonce
       }}
    else
      _ -> {:error, :offline}
    end
  end

  @doc """
  Contratos entre partes do endereço, já no formato que o navegador lê (endereços `brdc1…`, números como
  texto, porque valores vão a 2^64 - 1).
  """
  @spec contracts(String.t()) :: {:ok, [map()]} | {:error, :offline}
  def contracts(address) do
    with endpoint when endpoint != nil <- endpoint(),
         {:ok, hash} <- Address.decode(address),
         {:ok, list} <- Client.contracts_of(endpoint, hash) do
      {:ok, Enum.map(list, &for_browser/1)}
    else
      _ -> {:error, :offline}
    end
  end

  defp for_browser(c) do
    %{
      id: c.id,
      template: c.template,
      a: Bech32m.encode("brdc", c.a),
      b: Bech32m.encode("brdc", c.b),
      state: c.state,
      escrow: Integer.to_string(c.escrow),
      terms: Map.new(c.terms, fn {k, v} -> {k, Integer.to_string(v)} end),
      vars: Map.new(c.vars, fn {k, v} -> {k, Integer.to_string(v)} end)
    }
  end

  @doc "Repassa uma transação assinada (bytes) ao nó."
  @spec submit(binary()) :: {:ok, <<_::256>>} | {:error, atom()}
  def submit(tx_bin) do
    case endpoint() do
      nil -> {:error, :offline}
      endpoint -> normalize(Client.submit_tx(endpoint, tx_bin))
    end
  end

  defp normalize({:ok, id}), do: {:ok, id}
  defp normalize({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp normalize({:error, _}), do: {:error, :offline}
end
