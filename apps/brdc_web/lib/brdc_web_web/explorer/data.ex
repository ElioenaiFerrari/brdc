defmodule BrdcWebWeb.Explorer.Data do
  @moduledoc """
  Dados do explorador: lê **só pela porta pública** de um nó (`BrdcNode.Client`), sem chave nenhuma, e devolve
  mapas prontos para a tela. Nada aqui escreve: o explorador não envia transações.

  O certificado de cada bloco é **conferido aqui** (mais de 2/3 dos validadores assinaram aquele bloco). Como a
  página não tem as chaves da gênese, usa as que o próprio nó informa e a tela diz isso (confiança parcial).
  """
  alias BrdcCrypto.{Address, Bech32m}
  alias BrdcNode.{Client, Explorer}
  alias BrdcWebWeb.Wallet.Chain

  @latest 12
  @pending 20
  @history 50

  @type query ::
          {:block, pos_integer()}
          | {:tx, <<_::256>>}
          | {:account, String.t(), <<_::256>>}
          | :unknown

  @doc "O que a pessoa digitou na busca: altura, id de transação (64 hexadecimais) ou endereço `brdc1…`."
  @spec classify(String.t()) :: query()
  def classify(text) when is_binary(text) do
    q = String.trim(text)

    cond do
      q =~ ~r/^\d{1,12}$/ -> classify_height(q)
      q =~ ~r/^[0-9a-fA-F]{64}$/ -> classify_id(q)
      String.starts_with?(q, Address.hrp() <> "1") -> classify_address(q)
      true -> :unknown
    end
  end

  defp classify_id(q) do
    case Base.decode16(q, case: :mixed) do
      {:ok, <<_::256>> = id} -> {:tx, id}
      _ -> :unknown
    end
  end

  defp classify_height(q) do
    case String.to_integer(q) do
      h when h > 0 -> {:block, h}
      _ -> :unknown
    end
  end

  defp classify_address(q) do
    case Address.decode(q) do
      {:ok, hash} -> {:account, q, hash}
      _ -> :unknown
    end
  end

  @doc "Endereço `brdc1…` de um hash de conta."
  @spec address(<<_::256>>) :: String.t()
  def address(hash), do: Bech32m.encode(Address.hrp(), hash)

  @doc "Visão geral: estado da rede, últimos blocos, pendentes e validadores."
  @spec overview() :: {:ok, map()} | {:error, :offline}
  def overview do
    with ep when ep != nil <- Chain.endpoint(),
         {:ok, st} <- Client.status(ep),
         {:ok, blocks} <- Client.blocks(ep, 0, @latest),
         {:ok, pending} <- Client.mempool(ep, @pending),
         {:ok, validators} <- Client.validators(ep) do
      {:ok,
       %{
         status: st,
         blocks: blocks,
         pending: Enum.map(pending, &present_tx(&1.tx, &1.id)),
         validators: Enum.map(validators, &%{pub: &1, address: Address.from_public_key(&1)})
       }}
    else
      _ -> {:error, :offline}
    end
  end

  @doc "Um bloco, com o certificado conferido e as transações apresentadas."
  @spec block(pos_integer()) :: {:ok, map()} | {:error, :offline | :not_found}
  def block(height) do
    with ep when ep != nil <- Chain.endpoint(),
         {:ok, st} <- Client.status(ep) do
      case Client.block(ep, height) do
        {:ok, r} -> {:ok, present_block(r, st)}
        {:error, "not_found"} -> {:error, :not_found}
        {:error, _} -> {:error, :offline}
      end
    else
      _ -> {:error, :offline}
    end
  end

  defp present_block(r, st) do
    b = r.block

    %{
      height: b.height,
      hash: r.hash,
      prev_hash: b.prev_hash,
      time: b.time,
      proposer: address(b.proposer),
      state_root: b.state_root,
      txs:
        b.txs
        |> Enum.with_index()
        |> Enum.map(fn {tx, i} -> present_tx(tx, BrdcLedger.Tx.id(tx), i) end),
      verified: r.verified,
      reason: r.reason,
      trust: r.trust,
      signers: signers(r.certificate),
      latest: st.height,
      chain_id: st.chain_id
    }
  end

  defp signers(nil), do: []

  defp signers(cert),
    do: cert |> BrdcConsensus.Certificate.signers() |> Enum.map(&Address.from_public_key/1)

  @doc "Uma transação pelo id."
  @spec tx(<<_::256>>) :: {:ok, map()} | {:error, :offline | :not_found}
  def tx(id) do
    case Chain.endpoint() do
      nil -> {:error, :offline}
      ep -> ep |> Client.tx(id) |> present_found_tx(id)
    end
  end

  defp present_found_tx({:ok, r}, id) do
    {:ok,
     r.tx
     |> present_tx(id)
     |> Map.merge(%{height: r.height, index: r.index, time: r.time, block_hash: r.block_hash})}
  end

  defp present_found_tx({:error, "not_found"}, _id), do: {:error, :not_found}
  defp present_found_tx({:error, _}, _id), do: {:error, :offline}

  @doc "Uma conta: saldo e histórico."
  @spec account(String.t(), <<_::256>>) :: {:ok, map()} | {:error, :offline}
  def account(addr, hash) do
    with ep when ep != nil <- Chain.endpoint(),
         {:ok, acc} <- Client.account(ep, hash),
         {:ok, hist} <- Client.account_history(ep, hash, @history) do
      {:ok,
       %{
         address: addr,
         balance: acc.balance,
         pending_balance: acc.pending_balance,
         nonce: acc.nonce,
         history:
           Enum.map(
             hist,
             &Map.merge(&1, %{
               label: Explorer.kind_label(&1.kind),
               id_hex: Explorer.hex(&1.id, full: true)
             })
           )
       }}
    else
      _ -> {:error, :offline}
    end
  end

  defp present_tx(tx, id, index \\ nil) do
    d = Explorer.describe(tx)

    %{
      id: id,
      id_hex: Explorer.hex(id, full: true),
      index: index,
      kind: tx.kind,
      label: Explorer.kind_label(tx.kind),
      from: Address.from_public_key(tx.sender_pub),
      to: d |> Map.get(:to) |> then(&(&1 && address(&1))),
      amount: Map.get(d, :amount),
      fee: tx.fee,
      nonce: tx.nonce,
      detail: Map.drop(d, [:to, :amount])
    }
  end
end
