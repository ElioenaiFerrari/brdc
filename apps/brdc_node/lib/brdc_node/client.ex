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
         {:ok,
          [
            chain,
            height,
            time,
            supply,
            last,
            pending,
            base,
            per_byte,
            contract_fee,
            credential_fee,
            asset_step_fee
          ]} <-
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
         contract_fee: contract_fee,
         credential_fee: credential_fee,
         asset_step_fee: asset_step_fee
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

  @doc "Credenciais cujo titular é o endereço."
  @spec credentials_of(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def credentials_of({host, port}, <<_::256>> = addr) do
    list_query(host, port, :query, <<2, addr::binary>>, Handler.cred_schema(), fn [
                                                                                    id,
                                                                                    type,
                                                                                    subject,
                                                                                    data,
                                                                                    ref,
                                                                                    status,
                                                                                    issued,
                                                                                    active,
                                                                                    expires
                                                                                  ] ->
      %{
        id: id,
        type: type,
        subject: subject,
        data: data,
        ref: ref,
        status: status,
        issued_at: issued,
        active_at: active,
        expires_at: expires
      }
    end)
  end

  @doc "Bens que o endereço possui ou está comprando, com a negociação em curso."
  @spec assets_of(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def assets_of({host, port}, <<_::256>> = addr) do
    list_query(host, port, :query, <<4, addr::binary>>, Handler.asset_schema(), fn [
                                                                                     id,
                                                                                     class,
                                                                                     meta,
                                                                                     rev,
                                                                                     liens,
                                                                                     role,
                                                                                     status,
                                                                                     other,
                                                                                     price,
                                                                                     deadline,
                                                                                     window
                                                                                   ] ->
      %{
        id: id,
        class: class,
        meta: meta,
        rev: rev,
        liens: liens,
        role: role,
        deal: status,
        other: other,
        price: price,
        deadline: deadline,
        veto_window: window
      }
    end)
  end

  @doc "Tipos de credencial cujo órgão inclui a chave pública (quem pode assinar emissões)."
  @spec types_for(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def types_for({host, port}, <<_::256>> = pub) do
    list_query(host, port, :query, <<3, pub::binary>>, Handler.type_schema(), fn [
                                                                                   id,
                                                                                   threshold,
                                                                                   size,
                                                                                   privacy,
                                                                                   contest,
                                                                                   validity,
                                                                                   ref_type
                                                                                 ] ->
      %{
        id: id,
        threshold: threshold,
        organ_size: size,
        privacy: if(privacy == 1, do: "private", else: "public"),
        contest_window: contest,
        validity: validity,
        ref_type: ref_type
      }
    end)
  end

  @doc "Propõe uma emissão de credencial (campos); devolve o id da proposta."
  @spec propose(endpoint(), map()) :: {:ok, <<_::256>>} | {:error, term()}
  def propose({host, port}, %{type: t, id: id, subject: s, data: d, ref: r}) do
    body = <<1>> <> Encoding.encode(Handler.fields_schema(), [t, id, s, d, r])

    case PublicPort.request(host, port, :proposal, body) do
      {:ok, <<_::256>> = pid} -> {:ok, pid}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} when is_binary(reason) -> {:error, String.to_atom(reason)}
      {:error, _} = err -> err
    end
  end

  @doc "Envia a aprovação (`chave ‖ assinatura`) de um membro. Devolve quantas aprovações a proposta tem."
  @spec approve(endpoint(), <<_::256>>, binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def approve({host, port}, <<_::256>> = id, <<_::768>> = approval) do
    case PublicPort.request(host, port, :proposal, <<2, id::binary, approval::binary>>) do
      {:ok, <<n::32>>} -> {:ok, n}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} when is_binary(reason) -> {:error, String.to_atom(reason)}
      {:error, _} = err -> err
    end
  end

  @doc "Propostas abertas dos órgãos de que a chave faz parte."
  @spec proposals_for(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def proposals_for({host, port}, <<_::256>> = pub) do
    list_query(host, port, :proposal, <<3, pub::binary>>, Handler.proposal_schema(), fn [
                                                                                          id,
                                                                                          type,
                                                                                          cred_id,
                                                                                          subject,
                                                                                          data,
                                                                                          ref,
                                                                                          approvals,
                                                                                          threshold
                                                                                        ] ->
      %{
        id: id,
        type: type,
        cred_id: cred_id,
        subject: subject,
        data: data,
        ref: ref,
        approvals: approvals,
        threshold: threshold
      }
    end)
  end

  defp list_query(host, port, kind, body, schema, build) do
    with {:ok, bin} <- PublicPort.request(host, port, kind, body),
         {:ok, [entries]} <- Encoding.decode([{:list, :bytes}], bin) do
      decode_entries(entries, schema, build)
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  defp decode_entries(entries, schema, build) do
    entries
    |> Enum.reduce_while({:ok, []}, fn e, {:ok, acc} ->
      case Encoding.decode(schema, e) do
        {:ok, fields} -> {:cont, {:ok, [build.(fields) | acc]}}
        _ -> {:halt, {:error, :bad_response}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
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
