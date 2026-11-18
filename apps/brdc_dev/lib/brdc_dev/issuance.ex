defmodule BrdcDev.Issuance do
  @moduledoc """
  SIMULA a produção da moeda (o ciclo de uma stablecoin lastreada): os emissores de TESTE atestam a reserva em
  reais, emitem BRDC (mint, M de N), e resgatam queimando (burn, M de N). As chaves dos emissores são as de
  `net/` (papéis `i1` e `i2`, 2 de 2). Só desenvolvimento.

  A regra do projeto (ADR-0002/0009): **1 BRDC = R$ 1**, com reserva atestada pelos emissores; a rede só
  **informa** a cobertura (reserva atestada contra o que circula), não prova a reserva e não congela nada.
  """
  alias BrdcCrypto.{Address, Ed25519}
  alias BrdcDev.{Chain, Devnet}
  alias BrdcLedger.Tx
  alias BrdcNode.Client

  @issuers ["i1", "i2"]

  @type devnet :: %{genesis: map(), seeds: map()}

  @doc "Emite `units` (mint) para `to_hash`, aprovado pelos emissores de teste. `ref` identifica o depósito."
  @spec mint(Chain.endpoint(), devnet(), <<_::256>>, pos_integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def mint(endpoint, devnet, to_hash, units, ref) when units > 0 do
    doc = Tx.issuance_doc(:mint, devnet.genesis.chain_id, to_hash, units, ref)
    payload = Tx.issuance_payload(to_hash, units, ref, approvals(devnet, doc, @issuers))
    sender(endpoint, devnet, Tx.mint_kind(), payload)
  end

  @doc """
  Queima `units` da conta de `holder_seed` (resgate): o titular assina e os emissores aprovam. Só quem tem a
  chave da conta consegue (a regra do ledger: `conta == remetente`).
  """
  @spec burn(Chain.endpoint(), devnet(), <<_::256>>, pos_integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def burn(endpoint, devnet, holder_seed, units, ref) when units > 0 do
    holder = Address.hash(Ed25519.public_key(holder_seed))
    doc = Tx.issuance_doc(:burn, devnet.genesis.chain_id, holder, units, ref)
    payload = Tx.issuance_payload(holder, units, ref, approvals(devnet, doc, @issuers))

    with {:ok, sent} <- Chain.send_tx(endpoint, holder_seed, Tx.burn_kind(), payload, 0) do
      {:ok, Map.put(sent, :sender, holder)}
    end
  end

  @doc "Os emissores de teste atestam que há `reserve` unidades (reais, mesma escala do BRDC) em caixa."
  @spec attest(Chain.endpoint(), devnet(), non_neg_integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def attest(endpoint, devnet, reserve, ref) do
    with {:ok, supply} <- Client.supply(endpoint) do
      seq = if supply.attestation, do: supply.attestation.seq + 1, else: 1
      doc = Tx.attestation_doc(devnet.genesis.chain_id, seq, reserve, ref)

      sender(
        endpoint,
        devnet,
        Tx.attestation_kind(),
        Tx.attestation_payload(seq, reserve, ref, approvals(devnet, doc, @issuers))
      )
    end
  end

  @doc "Como `mint/5`, mas aprovado só pelos emissores listados em `roles` (para mostrar que M-de-N recusa)."
  @spec mint_with(Chain.endpoint(), devnet(), <<_::256>>, pos_integer(), String.t(), [String.t()]) ::
          {:ok, map()} | {:error, term()}
  def mint_with(endpoint, devnet, to_hash, units, ref, roles) do
    doc = Tx.issuance_doc(:mint, devnet.genesis.chain_id, to_hash, units, ref)
    payload = Tx.issuance_payload(to_hash, units, ref, approvals(devnet, doc, roles))
    sender(endpoint, devnet, Tx.mint_kind(), payload)
  end

  # quem envia mint e atestado é o emissor i1 (o ledger confere as aprovações, não o remetente)
  defp sender(endpoint, devnet, kind, payload) do
    seed = Devnet.seed!(devnet, "i1")

    with {:ok, sent} <- Chain.send_tx(endpoint, seed, kind, payload, 0) do
      {:ok, Map.put(sent, :sender, Address.hash(Ed25519.public_key(seed)))}
    end
  end

  defp approvals(devnet, doc, roles),
    do: for(role <- roles, do: Tx.approval(doc, Devnet.seed!(devnet, role)))
end
