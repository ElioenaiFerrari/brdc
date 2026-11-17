defmodule BrdcDev.Funding do
  @moduledoc """
  SIMULA os emissores de teste criando BRDC (mint M-de-N) para um endereço. Só desenvolvimento: usa as
  sementes dos emissores guardadas em `net/`. A transação segue o caminho normal: vai ao nó pela porta
  pública e entra no próximo bloco.
  """
  alias BrdcCrypto.{Account, Ed25519}
  alias BrdcLedger.Tx
  alias BrdcNode.Client

  @spec mint(Client.endpoint(), %{genesis: map(), seeds: map()}, <<_::256>>, pos_integer()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def mint(endpoint, %{genesis: genesis, seeds: seeds}, addr_hash, units) when units > 0 do
    chain_id = genesis.chain_id
    ref = "dev-fund-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    doc = Tx.issuance_doc(:mint, chain_id, addr_hash, units, ref)
    approvals = for role <- ["i1", "i2"], do: Tx.approval(doc, Map.fetch!(seeds, role))

    # quem envia é o emissor i1 (o mint não cobra taxa mínima); o nonce vem do nó
    sender_seed = Map.fetch!(seeds, "i1")
    sender_hash = BrdcCrypto.Address.hash(Ed25519.public_key(sender_seed))

    with {:ok, acc} <- Client.account(endpoint, sender_hash) do
      tx =
        %Tx{
          chain_id: chain_id,
          kind: Tx.mint_kind(),
          nonce: acc.pending_nonce,
          fee: 0,
          sender_pub: Account.from_seed(sender_seed).public_key,
          payload: Tx.issuance_payload(addr_hash, units, ref, approvals)
        }
        |> Tx.sign(sender_seed)

      Client.submit_tx(endpoint, Tx.encode(tx))
    end
  end
end
