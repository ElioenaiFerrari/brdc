defmodule BrdcLedger.Tx do
  @moduledoc """
  Transação assinada (Fase 2). A assinatura cobre **todos** os campos, inclusive o
  `chain_id` (impede reaproveitar a transação em outra rede) e o `nonce` (impede replay).

  Campos: `chain_id`, `kind`, `nonce`, `fee`, `sender_pub`, `payload`, `signature`.
  O remetente é o endereço derivado de `sender_pub`. Tipos (`kind`):
  `1` transferência, `2` mint, `3` burn, `4` atestado de reserva, `5` a `13` bens (classe,
  registro, oferta, aceite, cancelamento, veto, finalização, gravame, remoção de gravame),
  `14` a `19` credenciais (tipo, emissão, contestação, veto, ativação, revogação).
  """
  alias BrdcCrypto.{Address, Ed25519, Encoding, Hash}

  @transfer 1
  @mint 2
  @burn 3
  @attestation 4

  @enforce_keys [:chain_id, :kind, :nonce, :fee, :sender_pub, :payload]
  defstruct [:chain_id, :kind, :nonce, :fee, :sender_pub, :payload, signature: nil]

  @type t :: %__MODULE__{
          chain_id: String.t(),
          kind: 1..19,
          nonce: non_neg_integer(),
          fee: non_neg_integer(),
          sender_pub: <<_::256>>,
          payload: binary(),
          signature: nil | <<_::512>>
        }

  @body [:string, :u8, :u64, :u64, {:fixed, 32}, :bytes]
  @signed @body ++ [{:fixed, 64}]

  def transfer_kind, do: @transfer
  def mint_kind, do: @mint
  def burn_kind, do: @burn
  def attestation_kind, do: @attestation

  @doc "Endereço (32 bytes de hash) do remetente."
  @spec sender(t()) :: <<_::256>>
  def sender(%__MODULE__{sender_pub: pub}), do: Address.hash(pub)

  @doc "Bytes que são assinados (tudo, menos a assinatura)."
  @spec signing_bytes(t()) :: binary()
  def signing_bytes(%__MODULE__{} = t) do
    Encoding.encode(@body, [t.chain_id, t.kind, t.nonce, t.fee, t.sender_pub, t.payload])
  end

  @doc "Assina com a semente privada do remetente (a chave pública tem de bater)."
  @spec sign(t(), <<_::256>>) :: t()
  def sign(%__MODULE__{} = t, <<_::256>> = seed) do
    %{t | signature: Ed25519.sign(Hash.tagged("brdc/tx", signing_bytes(t)), seed)}
  end

  @doc "A assinatura confere com a chave pública da própria transação?"
  @spec valid_signature?(t()) :: boolean()
  def valid_signature?(%__MODULE__{signature: <<_::512>> = sig, sender_pub: pub} = t) do
    Ed25519.verify(Hash.tagged("brdc/tx", signing_bytes(t)), sig, pub)
  end

  def valid_signature?(_), do: false

  @doc "Identificador da transação (hash do conteúdo assinado)."
  @spec id(t()) :: <<_::256>>
  def id(%__MODULE__{} = t), do: Hash.tagged("brdc/txid", encode(t))

  @doc "Codificação completa (com assinatura)."
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{signature: <<_::512>> = sig} = t) do
    Encoding.encode(@signed, [t.chain_id, t.kind, t.nonce, t.fee, t.sender_pub, t.payload, sig])
  end

  @doc "Decodifica; recusa lixo, sobras e tipo desconhecido."
  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(bin) when is_binary(bin) do
    case Encoding.decode(@signed, bin) do
      {:ok, [chain, kind, nonce, fee, pub, payload, sig]}
      when kind in 1..19 ->
        {:ok,
         %__MODULE__{
           chain_id: chain,
           kind: kind,
           nonce: nonce,
           fee: fee,
           sender_pub: pub,
           payload: payload,
           signature: sig
         }}

      _ ->
        {:error, :malformed}
    end
  end

  # --- cargas úteis -------------------------------------------------------

  @doc "Carga de transferência."
  @spec transfer_payload(<<_::256>>, pos_integer()) :: binary()
  def transfer_payload(to, amount), do: Encoding.encode([{:fixed, 32}, :u64], [to, amount])

  @doc "Documento que os emissores assinam em mint (`:mint`) e burn (`:burn`)."
  @spec issuance_doc(:mint | :burn, String.t(), <<_::256>>, pos_integer(), String.t()) :: binary()
  def issuance_doc(kind, chain_id, account, amount, ref) do
    Hash.tagged(
      "brdc/issuance/#{kind}",
      Encoding.encode([:string, {:fixed, 32}, :u64, :string], [chain_id, account, amount, ref])
    )
  end

  @doc "Carga de mint/burn: conta, valor, referência única e aprovações (`pub ‖ assinatura`, 96 bytes)."
  @spec issuance_payload(<<_::256>>, pos_integer(), String.t(), [binary()]) :: binary()
  def issuance_payload(account, amount, ref, approvals) do
    Encoding.encode([{:fixed, 32}, :u64, :string, {:list, :bytes}], [
      account,
      amount,
      ref,
      approvals
    ])
  end

  @doc "Uma aprovação de emissor sobre `doc`."
  @spec approval(binary(), <<_::256>>) :: binary()
  def approval(doc, <<_::256>> = seed), do: Ed25519.public_key(seed) <> Ed25519.sign(doc, seed)

  @doc "Documento que os emissores assinam num atestado de reserva (total em unidades mínimas de BRDC, 1 BRDC = R$ 1)."
  @spec attestation_doc(String.t(), pos_integer(), non_neg_integer(), String.t()) :: binary()
  def attestation_doc(chain_id, seq, reserve, ref) do
    Hash.tagged(
      "brdc/attestation",
      Encoding.encode([:string, :u64, :u64, :string], [chain_id, seq, reserve, ref])
    )
  end

  @doc "Carga do atestado: sequência, reserva, referência (ex.: extrato ou auditoria) e aprovações."
  @spec attestation_payload(pos_integer(), non_neg_integer(), String.t(), [binary()]) :: binary()
  def attestation_payload(seq, reserve, ref, approvals) do
    Encoding.encode([:u64, :u64, :string, {:list, :bytes}], [seq, reserve, ref, approvals])
  end
end
