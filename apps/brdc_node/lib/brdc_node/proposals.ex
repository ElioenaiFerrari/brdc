defmodule BrdcNode.Proposals do
  @moduledoc """
  Propostas de assinatura coletiva (Fase 6/7): um membro de um órgão propõe uma emissão de credencial; os
  outros membros assinam; com M aprovações, qualquer um monta e envia a transação.

  **Puro**: `(armazém, estado do ledger, …) → armazém'`. O nó **não confia no que recebe**: a proposta traz só
  os **campos**; o documento a assinar é **recalculado aqui** (`Credentials.issue_doc/6`) e cada aprovação é
  conferida contra o órgão do tipo, com chaves distintas. Nada nelas é segredo (são assinaturas sobre um
  documento público), então o armazém pode ficar num nó e ser repassado.

  Limites: no máximo #{200} propostas; uma proposta de emissão por `cred_id`; some quando a credencial já existe.
  """
  alias BrdcCrypto.{Encoding, Hash}
  alias BrdcLedger.{Approvals, Credentials, State}

  @max 200
  @fields [:string, :string, {:fixed, 32}, :bytes, :string]

  @type fields :: %{
          type: String.t(),
          id: String.t(),
          subject: <<_::256>>,
          data: binary(),
          ref: String.t()
        }
  @type proposal :: %{
          id: <<_::256>>,
          kind: :credential_issue,
          fields: fields(),
          approvals: [binary()]
        }
  @type store :: %{<<_::256>> => proposal()}

  @spec new() :: store()
  def new, do: %{}

  @doc "Identificador da proposta: hash dos campos (a mesma proposta tem sempre o mesmo id)."
  @spec id_of(fields()) :: <<_::256>>
  def id_of(f) do
    Hash.tagged(
      "brdc/proposal/credential_issue",
      Encoding.encode(@fields, [f.type, f.id, f.subject, f.data, f.ref])
    )
  end

  @doc "Documento que os membros assinam (recalculado, nunca recebido pronto)."
  @spec doc(State.t(), fields()) :: binary()
  def doc(%State{params: p}, f),
    do: Credentials.issue_doc(p.chain_id, f.type, f.id, f.subject, f.data, f.ref)

  @doc "Registra uma proposta de emissão. Idempotente: a mesma proposta devolve o mesmo id."
  @spec put(store(), State.t(), fields()) :: {:ok, store(), <<_::256>>} | {:error, atom()}
  def put(store, %State{} = state, f) do
    id = id_of(f)

    cond do
      Map.has_key?(store, id) -> {:ok, store, id}
      map_size(store) >= @max -> {:error, :too_many_proposals}
      true -> add(store, state, f, id)
    end
  end

  defp add(store, state, f, id) do
    with {:ok, _type} <- Credentials.check_issue(state, f.type, f.id, f.subject, f.data, f.ref),
         :ok <- no_open_proposal_for(store, f.id) do
      {:ok, Map.put(store, id, %{id: id, kind: :credential_issue, fields: f, approvals: []}), id}
    end
  end

  defp no_open_proposal_for(store, cred_id) do
    if Enum.any?(store, fn {_, p} -> p.fields.id == cred_id end),
      do: {:error, :proposal_exists},
      else: :ok
  end

  @doc "Acrescenta a aprovação de um membro do órgão (`chave ‖ assinatura`, 96 bytes). Duplicada não conta."
  @spec approve(store(), State.t(), <<_::256>>, binary()) ::
          {:ok, store(), non_neg_integer()} | {:error, atom()}
  def approve(store, %State{} = state, id, approval) when is_binary(approval) do
    with {:ok, p} <- Map.fetch(store, id) |> ok_or(:no_proposal),
         {:ok, type} <-
           Credentials.check_issue(
             state,
             p.fields.type,
             p.fields.id,
             p.fields.subject,
             p.fields.data,
             p.fields.ref
           ),
         [signer] <- Approvals.signers(doc(state, p.fields), [approval], type.organ) do
      if Enum.any?(p.approvals, &(binary_part(&1, 0, 32) == signer)) do
        {:ok, store, length(p.approvals)}
      else
        p = %{p | approvals: p.approvals ++ [approval]}
        {:ok, Map.put(store, id, p), length(p.approvals)}
      end
    else
      {:error, _} = err -> err
      _ -> {:error, :bad_approval}
    end
  end

  @doc "Propostas de órgãos de que a chave `pub` faz parte, com o limite (M) do tipo."
  @spec list_for(store(), State.t(), <<_::256>>) :: [map()]
  def list_for(store, %State{} = state, pub) do
    for {_, p} <- store,
        {:ok, type} <- [
          Credentials.check_issue(
            state,
            p.fields.type,
            p.fields.id,
            p.fields.subject,
            p.fields.data,
            p.fields.ref
          )
        ],
        pub in type.organ do
      Map.put(p, :threshold, type.threshold)
    end
    |> Enum.sort_by(& &1.id)
  end

  @doc "Descarta propostas cuja credencial já existe (emitida) ou cujo tipo sumiu."
  @spec prune(store(), State.t()) :: store()
  def prune(store, %State{} = state) do
    store
    |> Enum.filter(fn {_, p} ->
      match?(
        {:ok, _},
        Credentials.check_issue(
          state,
          p.fields.type,
          p.fields.id,
          p.fields.subject,
          p.fields.data,
          p.fields.ref
        )
      )
    end)
    |> Map.new()
  end

  defp ok_or({:ok, v}, _), do: {:ok, v}
  defp ok_or(:error, reason), do: {:error, reason}
end
