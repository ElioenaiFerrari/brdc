defmodule BrdcDev.Authority do
  @moduledoc """
  SIMULA as autoridades raiz de teste criando um tipo de credencial (M-de-N das autoridades `a1` e `a2` de
  `net/`). Só desenvolvimento. O remetente é o emissor `i1`: para pagar a taxa de criação de tipo, ele recebe
  antes um pouco de BRDC de teste (mint dos emissores de teste).
  """
  alias BrdcCrypto.{Account, Address, Ed25519}
  alias BrdcDev.Funding
  alias BrdcLedger.{Approvals, Credentials}
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
end
