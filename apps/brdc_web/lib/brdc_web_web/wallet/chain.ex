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
          credential_fee: non_neg_integer(),
          asset_step_fee: non_neg_integer(),
          asset_register_fee: non_neg_integer(),
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
         credential_fee: st.credential_fee,
         asset_step_fee: st.asset_step_fee,
         asset_register_fee: st.asset_register_fee,
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

  @doc """
  Credenciais do titular, tipos que a chave pública pode assinar e propostas dos seus órgãos, no formato do
  navegador (endereços `brdc1…`, hexadecimal, números como texto).
  """
  @spec registry(String.t(), <<_::256>>) :: {:ok, map()} | {:error, :offline}
  def registry(address, <<_::256>> = pub) do
    with endpoint when endpoint != nil <- endpoint(),
         {:ok, hash} <- Address.decode(address),
         {:ok, creds} <- Client.credentials_of(endpoint, hash),
         {:ok, types} <- Client.types_for(endpoint, pub),
         {:ok, props} <- Client.proposals_for(endpoint, pub),
         {:ok, assets} <- Client.assets_of(endpoint, hash),
         {:ok, classes} <- Client.classes_for(endpoint, pub),
         {:ok, organ_assets} <- Client.organ_assets(endpoint, pub) do
      {:ok,
       %{
         credentials: Enum.map(creds, &cred_for_browser/1),
         types: Enum.map(types, &type_for_browser/1),
         proposals: Enum.map(props, &proposal_for_browser/1),
         assets: Enum.map(assets, &asset_for_browser/1),
         classes: Enum.map(classes, &class_for_browser/1),
         organ_assets: Enum.map(organ_assets, &asset_for_browser/1)
       }}
    else
      _ -> {:error, :offline}
    end
  end

  defp cred_for_browser(c) do
    %{
      id: c.id,
      type: c.type,
      data: Base.encode16(c.data, case: :lower),
      ref: c.ref,
      status: c.status,
      issued_at: Integer.to_string(c.issued_at),
      active_at: Integer.to_string(c.active_at),
      expires_at: Integer.to_string(c.expires_at)
    }
  end

  defp asset_for_browser(a) do
    %{
      id: a.id,
      class: a.class,
      meta: Base.encode16(a.meta, case: :lower),
      rev: a.rev,
      owner: Bech32m.encode("brdc", a.owner),
      lien_ids: a.lien_ids,
      lien_refs: a.lien_refs,
      role: a.role,
      deal: a.deal,
      other: Bech32m.encode("brdc", a.other),
      price: Integer.to_string(a.price),
      deadline: Integer.to_string(a.deadline),
      veto_window: Integer.to_string(a.veto_window)
    }
  end

  defp type_for_browser(t) do
    %{
      id: t.id,
      threshold: t.threshold,
      organ_size: t.organ_size,
      privacy: t.privacy,
      contest_window: Integer.to_string(t.contest_window),
      validity: Integer.to_string(t.validity)
    }
  end

  defp proposal_for_browser(p) do
    %{
      id: Base.encode16(p.id, case: :lower),
      kind: Atom.to_string(p.kind),
      fields: fields_for_browser(p.kind, p.fields),
      approvals: Enum.map(p.approvals, &Base.encode16(&1, case: :lower)),
      threshold: p.threshold
    }
  end

  # endereços em `brdc1…`, dados binários em hexadecimal, o resto como texto
  defp fields_for_browser(:credential_issue, f) do
    %{
      type: f.type,
      id: f.id,
      subject: Bech32m.encode("brdc", f.subject),
      data: hex(f.data),
      ref: f.ref
    }
  end

  defp fields_for_browser(:asset_register, f) do
    %{class: f.class, asset: f.asset, owner: Bech32m.encode("brdc", f.owner), meta: hex(f.meta)}
  end

  defp fields_for_browser(_kind, f), do: Map.new(f)

  defp hex(bin), do: Base.encode16(bin, case: :lower)

  defp class_for_browser(c) do
    %{
      id: c.id,
      threshold: c.threshold,
      organ_size: c.organ_size,
      veto_window: Integer.to_string(c.veto_window)
    }
  end

  @doc "Propõe uma emissão: o corpo (`<<1, campos>>`) já vem montado pelo navegador."
  @spec propose(binary()) :: {:ok, <<_::256>>} | {:error, atom()}
  def propose(<<1, fields::binary>>) do
    case endpoint() do
      nil ->
        {:error, :offline}

      {host, port} ->
        normalize(BrdcP2p.PublicPort.request(host, port, :proposal, <<1, fields::binary>>))
    end
  end

  def propose(_), do: {:error, :malformed}

  @doc "Repassa a aprovação (`chave ‖ assinatura`) de um membro a uma proposta."
  @spec approve(<<_::256>>, <<_::768>>) :: {:ok, non_neg_integer()} | {:error, atom()}
  def approve(<<_::256>> = id, <<_::768>> = approval) do
    case endpoint() do
      nil -> {:error, :offline}
      endpoint -> Client.approve(endpoint, id, approval) |> normalize()
    end
  end

  @doc "Repassa uma transação assinada (bytes) ao nó."
  @spec submit(binary()) :: {:ok, <<_::256>>} | {:error, atom()}
  def submit(tx_bin) do
    case endpoint() do
      nil -> {:error, :offline}
      endpoint -> normalize(Client.submit_tx(endpoint, tx_bin))
    end
  end

  defp normalize({:ok, <<_::256>> = id}), do: {:ok, id}
  defp normalize({:ok, n}) when is_integer(n), do: {:ok, n}

  defp normalize({:error, reason}) when is_binary(reason), do: {:error, reason_atom(reason)}

  defp normalize({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp normalize({:error, _}), do: {:error, :offline}

  # motivo vindo da rede: só vira átomo se já existir (nunca criamos átomos a partir de texto de fora)
  defp reason_atom(text) do
    String.to_existing_atom(text)
  rescue
    ArgumentError -> :rejected
  end
end
