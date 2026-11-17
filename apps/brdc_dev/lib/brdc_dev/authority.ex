defmodule BrdcDev.Authority do
  @moduledoc """
  SIMULA as autoridades raiz de teste criando um tipo de credencial (M-de-N das autoridades `a1` e `a2` de
  `net/`). Só desenvolvimento. O remetente é o emissor `i1`: para pagar a taxa de criação de tipo, ele recebe
  antes um pouco de BRDC de teste (mint dos emissores de teste).
  """
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcDev.Funding
  alias BrdcLedger.{Approvals, Assets, Credentials}
  alias BrdcNode.Client

  @spec create_type(Client.endpoint(), %{genesis: map(), seeds: map()}, map()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def create_type(endpoint, %{genesis: genesis, seeds: seeds} = devnet, attrs) do
    spec =
      Map.merge(
        %{contest: 60, validity: 0, privacy: 0, ref_type: "", revokes: 0, threshold: 1},
        attrs
      )

    doc = Credentials.type_doc(genesis.chain_id, spec)
    approvals = for role <- ["a1", "a2"], do: Approvals.approval(doc, Map.fetch!(seeds, role))

    sender_seed = Map.fetch!(seeds, "i1")
    sender_hash = Address.hash(Ed25519.public_key(sender_seed))

    with {:ok, _} <- Funding.mint(endpoint, devnet, sender_hash, 1_000_000),
         {:ok, status} <- Client.status(endpoint),
         {:ok, acc} <- Client.account(endpoint, sender_hash) do
      tx =
        %BrdcLedger.Tx{
          chain_id: genesis.chain_id,
          kind: 14,
          nonce: acc.pending_nonce,
          fee: status.transfer_base * 50,
          sender_pub: Account.from_seed(sender_seed).public_key,
          payload: Credentials.type_payload(spec, approvals)
        }
        |> BrdcLedger.Tx.sign(sender_seed)

      Client.submit_tx(endpoint, BrdcLedger.Tx.encode(tx))
    end
  end

  @doc """
  Cria uma classe de bens (autoridades de teste `a1` e `a2`). `organ` são as chaves públicas do órgão da classe.
  """
  @spec create_class(Client.endpoint(), map(), map()) :: {:ok, <<_::256>>} | {:error, term()}
  def create_class(
        endpoint,
        %{genesis: genesis, seeds: seeds} = devnet,
        %{id: id, organ: organ} = attrs
      ) do
    threshold = Map.get(attrs, :threshold, 1)
    window = Map.get(attrs, :veto_window, 60)
    doc = Assets.class_doc(genesis.chain_id, id, organ, threshold, window)
    approvals = for role <- ["a1", "a2"], do: Approvals.approval(doc, Map.fetch!(seeds, role))
    payload = Assets.class_payload(id, organ, threshold, window, approvals)
    send_as_funded(endpoint, devnet, 5, payload)
  end

  @doc """
  Registra um bem assinando como membros de TESTE do órgão (`organ_seeds`: as sementes dos membros).
  """
  @spec register_asset(Client.endpoint(), map(), [binary()], map()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def register_asset(endpoint, %{genesis: genesis} = devnet, organ_seeds, %{
        class: class,
        id: id,
        owner: owner,
        meta: meta
      }) do
    doc = Assets.register_doc(genesis.chain_id, class, id, owner, meta)
    approvals = for seed <- organ_seeds, do: Approvals.approval(doc, seed)

    send_as_funded(
      endpoint,
      devnet,
      6,
      Assets.register_payload(class, id, owner, meta, approvals)
    )
  end

  # o remetente é o emissor `i1`, que recebe antes BRDC de teste para a taxa
  defp send_as_funded(endpoint, %{genesis: genesis, seeds: seeds} = devnet, kind, payload) do
    sender_seed = Map.fetch!(seeds, "i1")
    sender_hash = Address.hash(Ed25519.public_key(sender_seed))

    with {:ok, _} <- Funding.mint(endpoint, devnet, sender_hash, 1_000_000),
         {:ok, status} <- Client.status(endpoint),
         {:ok, acc} <- Client.account(endpoint, sender_hash) do
      tx =
        %BrdcLedger.Tx{
          chain_id: genesis.chain_id,
          kind: kind,
          nonce: acc.pending_nonce,
          fee: status.asset_step_fee * 3,
          sender_pub: Account.from_seed(sender_seed).public_key,
          payload: payload
        }
        |> BrdcLedger.Tx.sign(sender_seed)

      Client.submit_tx(endpoint, BrdcLedger.Tx.encode(tx))
    end
  end
end
