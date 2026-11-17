defmodule BrdcNode.Handler do
  @moduledoc """
  Ponte entre a porta pública (`BrdcP2p.PublicPort`) e o nó. É o `handler` que o `PublicPort` chama para
  cada pedido, já com tipo e tamanho conferidos. Respostas em codificação determinística (ADR-0011):

  - `:status` → `[chain_id, altura, horário, oferta, hash do último bloco, pendentes, taxa-base, taxa por byte]`
  - `:get_account` (corpo: 32 bytes do endereço) → `[saldo, nonce, saldo com pendentes, nonce com pendentes]`
  - `:submit_tx` (corpo: transação assinada) → id de 32 bytes, ou o motivo da recusa
  - `:query` (`<<1, endereço>>` contratos · `<<2, endereço>>` credenciais do titular · `<<3, chave pública>>` tipos cujo órgão inclui a chave · `<<4, endereço>>` bens · `<<5, chave pública>>` classes do órgão · `<<6, chave pública>>` bens das classes do órgão)
  - `:proposal` (`<<1, tipo, campos>>` propõe (emissão, registro, veto, gravame) · `<<2, id, aprovação>>` aprova · `<<3, chave pública>>` lista as dos seus órgãos)
  - `:get_block` → ainda não suportado (o bloco não tem codificação de rede)
  """
  alias BrdcCrypto.Encoding
  alias BrdcNode.{Node, Proposals}

  @status [:string, :u64, :u64, :u64, :bytes, :u32, :u64, :u64, :u64, :u64, :u64, :u64]
  @contract [
    :string,
    :string,
    {:fixed, 32},
    {:fixed, 32},
    :string,
    :u64,
    {:list, :bytes},
    {:list, :bytes}
  ]
  @kv [:string, :u64]
  @cred [:string, :string, {:fixed, 32}, :bytes, :string, :string, :u64, :u64, :u64]
  @type_entry [:string, :u32, :u32, :u8, :u64, :u64, :string]
  @proposal [:bytes, :string, :bytes, {:list, :bytes}, :u32]
  @fields [:string, :string, {:fixed, 32}, :bytes, :string]
  @asset [
    :string,
    :string,
    :bytes,
    :u32,
    {:fixed, 32},
    {:list, :string},
    {:list, :string},
    :string,
    :string,
    {:fixed, 32},
    :u64,
    :u64,
    :u64
  ]
  @class [:string, :u32, :u32, :u64]
  @max_listed 100
  @max_contracts 100
  @account [:u64, :u64, :u64, :u64]

  @doc "Função de tratamento para o `PublicPort`."
  @spec fun(GenServer.server()) :: (atom(), binary() ->
                                      {:ok, binary()} | {:error, atom() | String.t()})
  def fun(node), do: fn kind, body -> handle(node, kind, body) end

  @doc false
  def handle(node, :status, _body) do
    s = Node.status(node)

    {:ok,
     Encoding.encode(@status, [
       s.chain_id,
       s.height,
       s.time,
       s.supply,
       s.last_hash || <<>>,
       s.pending,
       s.transfer_base,
       s.per_byte,
       s.contract_fee,
       s.credential_fee,
       s.asset_step_fee,
       s.asset_register_fee
     ])}
  end

  def handle(node, :get_account, <<addr::binary-size(32)>>) do
    confirmed = Node.account(node, addr)
    pending = Node.account(node, addr, pending: true)

    {:ok,
     Encoding.encode(@account, [
       confirmed.balance,
       confirmed.nonce,
       pending.balance,
       pending.nonce
     ])}
  end

  def handle(_node, :get_account, _), do: {:error, :bad_address}

  # consulta: `<<1, endereço::32>>` = contratos desse endereço (até 100, do estado confirmado)
  def handle(node, :query, <<1, addr::binary-size(32)>>) do
    entries =
      node
      |> Node.contracts_of(addr)
      |> Enum.take(@max_contracts)
      |> Enum.map(&encode_contract/1)

    {:ok, Encoding.encode([{:list, :bytes}], [entries])}
  end

  def handle(node, :query, <<2, addr::binary-size(32)>>) do
    entries =
      node
      |> Node.credentials_of(addr)
      |> Enum.take(@max_listed)
      |> Enum.map(fn c ->
        Encoding.encode(@cred, [
          c.id,
          c.type,
          c.subject,
          c.data,
          c.ref,
          Atom.to_string(c.status),
          c.issued_at,
          c.active_at,
          c.expires_at
        ])
      end)

    {:ok, Encoding.encode([{:list, :bytes}], [entries])}
  end

  def handle(node, :query, <<3, pub::binary-size(32)>>) do
    entries =
      node
      |> Node.types_for(pub)
      |> Enum.take(@max_listed)
      |> Enum.map(fn t ->
        privacy = if t.privacy == :private, do: 1, else: 0

        Encoding.encode(@type_entry, [
          t.id,
          t.threshold,
          length(t.organ),
          privacy,
          t.contest_window,
          t.validity,
          t.ref_type
        ])
      end)

    {:ok, Encoding.encode([{:list, :bytes}], [entries])}
  end

  def handle(node, :query, <<4, addr::binary-size(32)>>),
    do: {:ok, asset_list(Node.assets_of(node, addr))}

  def handle(node, :query, <<5, pub::binary-size(32)>>) do
    entries =
      node
      |> Node.classes_for(pub)
      |> Enum.take(@max_listed)
      |> Enum.map(fn c ->
        Encoding.encode(@class, [c.id, c.threshold, length(c.organ), c.veto_window])
      end)

    {:ok, Encoding.encode([{:list, :bytes}], [entries])}
  end

  def handle(node, :query, <<6, pub::binary-size(32)>>),
    do: {:ok, asset_list(Node.organ_assets(node, pub))}

  def handle(_node, :query, _), do: {:error, :bad_query}

  def handle(node, :proposal, <<1, kind_n, rest::binary>>) do
    with {:ok, kind} <- Proposals.kind_from_number(kind_n),
         {:ok, fields} <- Proposals.decode_fields(kind, rest),
         {:ok, pid} <- Node.propose(node, kind, fields) do
      {:ok, pid}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :malformed}
    end
  end

  def handle(node, :proposal, <<2, id::binary-size(32), approval::binary-size(96)>>) do
    case Node.approve(node, id, approval) do
      {:ok, n} -> {:ok, <<n::32>>}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle(node, :proposal, <<3, pub::binary-size(32)>>) do
    entries =
      node
      |> Node.proposals_for(pub)
      |> Enum.take(@max_listed)
      |> Enum.map(fn p ->
        Encoding.encode(@proposal, [
          p.id,
          Atom.to_string(p.kind),
          Proposals.encode_fields(p.kind, p.fields),
          p.approvals,
          p.threshold
        ])
      end)

    {:ok, Encoding.encode([{:list, :bytes}], [entries])}
  end

  def handle(_node, :proposal, _), do: {:error, :bad_proposal}

  def handle(node, :submit_tx, body) do
    case Node.submit(node, body) do
      {:ok, id} -> {:ok, id}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle(_node, _kind, _body), do: {:error, :unsupported}

  defp encode_contract(c) do
    Encoding.encode(@contract, [
      c.id,
      c.template,
      c.a,
      c.b,
      Atom.to_string(c.state),
      c.escrow,
      kv(c.terms),
      kv(c.vars)
    ])
  end

  defp kv(map),
    do: for({k, v} <- Enum.sort(map), do: Encoding.encode(@kv, [Atom.to_string(k), v]))

  @doc false
  def asset_schema, do: @asset
  @doc false
  def cred_schema, do: @cred
  @doc false
  def type_schema, do: @type_entry
  @doc false
  def class_schema, do: @class
  @doc false
  def proposal_schema, do: @proposal
  @doc false
  def fields_schema, do: @fields
  @doc false
  def contract_schema, do: @contract
  @doc false
  def kv_schema, do: @kv
  @doc false
  def status_schema, do: @status
  @doc false
  def account_schema, do: @account

  defp deal_fields(%{deal: nil}), do: {"none", <<0::256>>, 0, 0}

  defp deal_fields(%{deal: d, role: role}) do
    other = if role == "buyer", do: d.seller, else: d.buyer
    {Atom.to_string(d.status), other, d.price, d.deadline || 0}
  end

  # proposta de assinatura coletiva: `<<1, campos>>` propõe, `<<2, id, aprovação>>` aprova, `<<3, chave>>` lista

  defp asset_list(assets) do
    entries =
      assets
      |> Enum.take(@max_listed)
      |> Enum.map(fn a ->
        {status, other, price, deadline} = deal_fields(a)

        Encoding.encode(@asset, [
          a.id,
          a.class,
          a.meta,
          a.rev,
          a.owner,
          a.lien_ids,
          a.lien_refs,
          a.role,
          status,
          other,
          price,
          deadline,
          a.veto_window
        ])
      end)

    Encoding.encode([{:list, :bytes}], [entries])
  end
end
