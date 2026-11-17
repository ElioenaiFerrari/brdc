defmodule BrdcNode.Handler do
  @moduledoc """
  Ponte entre a porta pública (`BrdcP2p.PublicPort`) e o nó. É o `handler` que o `PublicPort` chama para
  cada pedido, já com tipo e tamanho conferidos. Respostas em codificação determinística (ADR-0011):

  - `:status` → `[chain_id, altura, horário, oferta, hash do último bloco, pendentes, taxa-base, taxa por byte]`
  - `:get_account` (corpo: 32 bytes do endereço) → `[saldo, nonce, saldo com pendentes, nonce com pendentes]`
  - `:submit_tx` (corpo: transação assinada) → id de 32 bytes, ou o motivo da recusa
  - `:query` (corpo `<<1, endereço>>`) → contratos desse endereço
  - `:get_block` → ainda não suportado (o bloco não tem codificação de rede)
  """
  alias BrdcCrypto.Encoding
  alias BrdcNode.Node

  @status [:string, :u64, :u64, :u64, :bytes, :u32, :u64, :u64, :u64]
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
       s.contract_fee
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

  def handle(_node, :query, _), do: {:error, :bad_query}

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
  def contract_schema, do: @contract
  @doc false
  def kv_schema, do: @kv
  @doc false
  def status_schema, do: @status
  @doc false
  def account_schema, do: @account
end
