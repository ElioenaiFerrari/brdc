defmodule BrdcNode.Client do
  @moduledoc """
  Cliente da porta pública de um nó (usado pela carteira web e pelas ferramentas). **Não confia no nó**:
  por ora só lê estado e envia transações já assinadas; as provas (certificado de commit, raiz de estado)
  chegam quando o nó tiver mais de um validador.
  """
  alias BrdcConsensus.Certificate
  alias BrdcCrypto.Encoding
  alias BrdcLedger.{Block, Tx}
  alias BrdcNode.{Handler, Proposals}
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
            asset_step_fee,
            asset_register_fee
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
         asset_step_fee: asset_step_fee,
         asset_register_fee: asset_register_fee
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
  def credentials_of({host, port}, <<_::256>> = addr),
    do: list_query(host, port, :query, <<2, addr::binary>>, Handler.cred_schema(), &cred_map/1)

  @doc "Credenciais dos tipos cujo órgão inclui a chave pública (para propor veto e revogação)."
  @spec organ_credentials(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def organ_credentials({host, port}, <<_::256>> = pub),
    do: list_query(host, port, :query, <<7, pub::binary>>, Handler.cred_schema(), &cred_map/1)

  defp cred_map([id, type, subject, data, ref, status, issued, active, expires]) do
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
  end

  @doc """
  Oferta e reserva: `%{minted, burned, supply, attestation}` (`attestation` é `nil` ou `%{seq, reserve, ref}`),
  mais `coverage`: `:none`, `{:covered, margem}` ou `{:under, falta}` (só informação, ADR-0009).
  """
  @spec supply({charlist(), pos_integer()}) :: {:ok, map()} | {:error, term()}
  def supply({host, port}) do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<8>>),
         {:ok, [minted, burned, seq, reserve, ref]} <-
           Encoding.decode([:u64, :u64, :u64, :u64, :string], bin) do
      supply = minted - burned
      att = if seq == 0, do: nil, else: %{seq: seq, reserve: reserve, ref: ref}

      coverage =
        cond do
          att == nil -> :none
          reserve >= supply -> {:covered, reserve - supply}
          true -> {:under, supply - reserve}
        end

      {:ok,
       %{minted: minted, burned: burned, supply: supply, attestation: att, coverage: coverage}}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  # --- explorador (somente leitura) -------------------------------------------------------------------------------

  @doc """
  Resumos de blocos, do mais novo ao mais antigo: até `count` com altura menor que `before` (`0` = do mais novo).
  São **informação do nó** (não provados); `block/3` entrega a prova.
  """
  @spec blocks(endpoint(), non_neg_integer(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def blocks({host, port}, before \\ 0, count \\ 20) when count in 1..100 do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<9, before::64, count::16>>),
         {:ok, [rows]} <- Encoding.decode([{:list, :bytes}], bin) do
      decode_rows(rows, [:u64, :u64, {:fixed, 32}, {:fixed, 32}, :u32, :u32], fn [
                                                                                   h,
                                                                                   t,
                                                                                   hash,
                                                                                   prop,
                                                                                   n,
                                                                                   sig
                                                                                 ] ->
        %{height: h, time: t, hash: hash, proposer: prop, tx_count: n, signers: sig}
      end)
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @doc """
  Um bloco **conferido**: o cliente checa que o certificado é do mesmo bloco e que tem **mais de 2/3** de
  precommits válidos dos validadores. Com `validators` (as chaves da gênese, fixadas por quem chama) a confiança é
  total (`trust: :pinned`); sem elas, usa as que o próprio nó informa (`trust: :node_reported`), que prova só a
  consistência interna. `verified: false` e o motivo aparecem se o certificado faltar ou não fechar.
  """
  @spec block(endpoint(), pos_integer(), [<<_::256>>] | nil) :: {:ok, map()} | {:error, term()}
  def block({host, port} = ep, height, validators \\ nil) do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<10, height::64>>),
         {:ok, [block_bin, cert_bin]} <- Encoding.decode([:bytes, :bytes], bin),
         {:ok, block} <- Block.decode(block_bin),
         {:ok, st} <- status(ep),
         {:ok, {pubs, trust}} <- validators_for(ep, validators) do
      {verified, why} = verify_cert(block, cert_bin, st.chain_id, pubs)

      cert =
        case Certificate.decode(cert_bin) do
          {:ok, c} -> c
          _ -> nil
        end

      {:ok,
       %{
         block: block,
         certificate: cert,
         verified: verified,
         reason: why,
         trust: trust,
         hash: Block.hash(block)
       }}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @doc "Uma transação pelo id (32 bytes): a transação, o bloco (altura, posição, hora) e o hash do bloco."
  @spec tx(endpoint(), <<_::256>>) :: {:ok, map()} | {:error, term()}
  def tx({host, port}, <<_::256>> = id) do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<11, id::binary>>),
         {:ok, [h, i, t, bh, tx_bin]} <-
           Encoding.decode([:u64, :u32, :u64, {:fixed, 32}, :bytes], bin),
         {:ok, tx} <- Tx.decode(tx_bin),
         true <- Tx.id(tx) == id do
      {:ok, %{tx: tx, id: id, height: h, index: i, time: t, block_hash: bh}}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @doc "Histórico de uma conta (do mais novo ao mais antigo): `%{id, height, time, kind, role}`."
  @spec account_history(endpoint(), <<_::256>>, pos_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def account_history({host, port}, <<_::256>> = addr, limit \\ 50) when limit in 1..200 do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<12, addr::binary, limit::16>>),
         {:ok, [rows]} <- Encoding.decode([{:list, :bytes}], bin) do
      decode_rows(rows, [{:fixed, 32}, :u64, :u64, :u8, :u8], fn [id, h, t, k, r] ->
        %{id: id, height: h, time: t, kind: k, role: if(r == 0, do: :sender, else: :receiver)}
      end)
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @doc "Transações pendentes (mempool), na ordem de chegada, já decodificadas e com o id."
  @spec mempool(endpoint(), pos_integer()) :: {:ok, [map()]} | {:error, term()}
  def mempool({host, port}, limit \\ 50) when limit in 1..200 do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<13, limit::16>>),
         {:ok, [rows]} <- Encoding.decode([{:list, :bytes}], bin) do
      decode_txs(rows)
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  @doc "As chaves dos validadores em vigor, **segundo o nó** (para conferir, fixe as da gênese)."
  @spec validators(endpoint()) :: {:ok, [<<_::256>>]} | {:error, term()}
  def validators({host, port}) do
    with {:ok, bin} <- PublicPort.request(host, port, :query, <<14>>),
         {:ok, [pubs]} <- Encoding.decode([{:list, :bytes}], bin),
         true <- Enum.all?(pubs, &(byte_size(&1) == 32)) do
      {:ok, pubs}
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_response}
    end
  end

  defp validators_for(ep, nil) do
    with {:ok, pubs} <- validators(ep), do: {:ok, {pubs, :node_reported}}
  end

  defp validators_for(_ep, pubs) when is_list(pubs), do: {:ok, {pubs, :pinned}}

  defp verify_cert(_block, "", _chain, _pubs), do: {false, :no_certificate}

  defp verify_cert(block, cert_bin, chain_id, pubs) do
    with {:ok, cert} <- Certificate.decode(cert_bin),
         true <- cert.height == block.height || {:error, :wrong_height},
         true <- cert.block_hash == Block.hash(block) || {:error, :different_block},
         :ok <- Certificate.verify(cert, chain_id, pubs) do
      {true, nil}
    else
      {:error, reason} -> {false, reason}
    end
  end

  defp decode_txs(rows) do
    rows
    |> Enum.reduce_while({:ok, []}, &add_tx/2)
    |> then(fn
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end)
  end

  defp add_tx(row, {:ok, acc}) do
    case Tx.decode(row) do
      {:ok, tx} -> {:cont, {:ok, [%{id: Tx.id(tx), tx: tx} | acc]}}
      _ -> {:halt, {:error, :bad_response}}
    end
  end

  defp decode_rows(rows, types, fun) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
      case Encoding.decode(types, row) do
        {:ok, fields} -> {:cont, {:ok, [fun.(fields) | acc]}}
        _ -> {:halt, {:error, :bad_response}}
      end
    end)
    |> then(fn
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end)
  end

  @doc "Bens que o endereço possui ou está comprando, com a negociação em curso."
  @spec assets_of(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def assets_of({host, port}, <<_::256>> = addr),
    do: list_query(host, port, :query, <<4, addr::binary>>, Handler.asset_schema(), &asset_map/1)

  @doc "Bens das classes cujo órgão inclui a chave pública (para propor veto e gravames)."
  @spec organ_assets(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def organ_assets({host, port}, <<_::256>> = pub),
    do: list_query(host, port, :query, <<6, pub::binary>>, Handler.asset_schema(), &asset_map/1)

  @doc "Classes de bens cujo órgão inclui a chave pública."
  @spec classes_for(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def classes_for({host, port}, <<_::256>> = pub) do
    list_query(host, port, :query, <<5, pub::binary>>, Handler.class_schema(), fn [
                                                                                    id,
                                                                                    threshold,
                                                                                    size,
                                                                                    window
                                                                                  ] ->
      %{id: id, threshold: threshold, organ_size: size, veto_window: window}
    end)
  end

  defp asset_map([
         id,
         class,
         meta,
         rev,
         owner,
         lien_ids,
         lien_refs,
         role,
         status,
         other,
         price,
         deadline,
         window
       ]) do
    %{
      id: id,
      class: class,
      meta: meta,
      rev: rev,
      owner: owner,
      lien_ids: lien_ids,
      lien_refs: lien_refs,
      role: role,
      deal: status,
      other: other,
      price: price,
      deadline: deadline,
      veto_window: window
    }
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
  def propose(endpoint, fields), do: propose(endpoint, :credential_issue, fields)

  @doc "Propõe uma ação de órgão (`BrdcNode.Proposals.kinds/0`); devolve o id da proposta."
  @spec propose(endpoint(), Proposals.kind(), map()) :: {:ok, <<_::256>>} | {:error, term()}
  def propose({host, port}, kind, fields) do
    body = <<1, Proposals.kind_number(kind)>> <> Proposals.encode_fields(kind, fields)

    case PublicPort.request(host, port, :proposal, body) do
      {:ok, <<_::256>> = pid} -> {:ok, pid}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} when is_binary(reason) -> {:error, reason_atom(reason)}
      {:error, _} = err -> err
    end
  end

  @doc "Envia a aprovação (`chave ‖ assinatura`) de um membro. Devolve quantas aprovações a proposta tem."
  @spec approve(endpoint(), <<_::256>>, binary()) :: {:ok, non_neg_integer()} | {:error, term()}
  def approve({host, port}, <<_::256>> = id, <<_::768>> = approval) do
    case PublicPort.request(host, port, :proposal, <<2, id::binary, approval::binary>>) do
      {:ok, <<n::32>>} -> {:ok, n}
      {:ok, _} -> {:error, :bad_response}
      {:error, reason} when is_binary(reason) -> {:error, reason_atom(reason)}
      {:error, _} = err -> err
    end
  end

  @doc "Propostas abertas dos órgãos de que a chave faz parte."
  @spec proposals_for(endpoint(), <<_::256>>) :: {:ok, [map()]} | {:error, term()}
  def proposals_for({host, port}, <<_::256>> = pub) do
    list_query(host, port, :proposal, <<3, pub::binary>>, Handler.proposal_schema(), fn [
                                                                                          id,
                                                                                          kind,
                                                                                          fields,
                                                                                          approvals,
                                                                                          threshold
                                                                                        ] ->
      kind = Enum.find(Proposals.kinds(), &(Atom.to_string(&1) == kind))
      %{id: id, kind: kind, fields: fields, approvals: approvals, threshold: threshold}
    end)
    |> decode_proposal_fields()
  end

  # os campos vêm codificados; decodifica por tipo (tipo desconhecido da rede vira erro, nunca átomo novo)
  defp decode_proposal_fields({:ok, list}) do
    Enum.reduce_while(list, {:ok, []}, fn p, {:ok, acc} ->
      with kind when kind != nil <- p.kind,
           {:ok, f} <- Proposals.decode_fields(kind, p.fields) do
        {:cont, {:ok, [%{p | fields: f} | acc]}}
      else
        _ -> {:halt, {:error, :bad_response}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp decode_proposal_fields(err), do: err

  defp reason_atom(text) do
    String.to_existing_atom(text)
  rescue
    ArgumentError -> :rejected
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
      {:error, reason} when is_binary(reason) -> {:error, reason_atom(reason)}
      {:error, _} = err -> err
    end
  end
end
