defmodule BrdcLedger.Executor do
  @moduledoc """
  Execução determinística de transações (Fase 2). Função pura: `(estado, tx) -> estado'` ou erro.

  Regras comuns: `chain_id` igual, assinatura válida, `nonce` igual ao da conta (impede replay
  e reordenação), taxa ≥ mínima, saldo cobre valor + taxa. A taxa sai da conta e vai para o
  `fee_pool` devolvido, que o bloco reparte entre os validadores (ADR-0014); aqui ela **não
  some**, para a oferta continuar sendo `emitido − queimado`.
  """
  alias BrdcCrypto.{Address, Encoding}
  alias BrdcLedger.{Approvals, Assets, Credentials, Params, State, Tx}

  @typedoc "Motivo da recusa: um átomo (ex.: `:bad_nonce`, `:not_enough_approvals`, `:has_lien`)."
  @type error :: atom()

  @doc "Taxa mínima de uma transação, pela tabela dos parâmetros (ADR-0014)."
  @spec min_fee(Params.t(), Tx.t()) :: non_neg_integer()
  def min_fee(%Params{} = p, %Tx{kind: 1} = tx),
    do: p.transfer_base + p.per_byte * byte_size(Tx.encode(tx))

  def min_fee(%Params{} = p, %Tx{kind: kind}) when kind in 5..13, do: Assets.min_fee(p, kind)

  def min_fee(%Params{} = p, %Tx{kind: kind}) when kind in 14..19,
    do: Credentials.min_fee(p, kind)

  def min_fee(%Params{}, %Tx{}), do: 0

  @doc "Aplica uma transação. Devolve `{:ok, estado, taxa_paga}` ou `{:error, motivo}`."
  @spec apply_tx(State.t(), Tx.t()) :: {:ok, State.t(), non_neg_integer()} | {:error, error()}
  def apply_tx(%State{} = s, %Tx{} = tx) do
    sender = Tx.sender(tx)
    acc = State.account(s, sender)

    with :ok <- check(tx.chain_id == s.params.chain_id, :wrong_chain),
         :ok <- check(Tx.valid_signature?(tx), :bad_signature),
         :ok <- check(tx.nonce == acc.nonce, :bad_nonce),
         :ok <- check(tx.fee >= min_fee(s.params, tx), :fee_too_low),
         :ok <- check(acc.balance >= tx.fee, :insufficient_funds),
         s1 =
           State.put_account(s, sender, %{
             acc
             | balance: acc.balance - tx.fee,
               nonce: acc.nonce + 1
           }),
         {:ok, s2} <- run(s1, sender, tx) do
      {:ok, s2, tx.fee}
    end
  end

  # --- transferência ------------------------------------------------------

  defp run(s, sender, %Tx{kind: 1, payload: payload}) do
    with {:ok, [to, amount]} <- decode(payload, [{:fixed, 32}, :u64]),
         :ok <- check(amount > 0, :bad_amount),
         from = State.account(s, sender),
         :ok <- check(from.balance >= amount, :insufficient_funds),
         s1 = State.put_account(s, sender, %{from | balance: from.balance - amount}),
         dest = State.account(s1, to),
         :ok <- check(dest.balance + amount <= State.max_u64(), :overflow) do
      {:ok, State.put_account(s1, to, %{dest | balance: dest.balance + amount})}
    end
  end

  # --- mint e burn: aprovados por M-de-N emissores -------------------------

  defp run(s, _sender, %Tx{kind: 2, payload: payload}) do
    with {:ok, {account, amount, ref, approvals}} <- issuance(payload),
         :ok <- check(amount > 0, :bad_amount),
         :ok <- check(not MapSet.member?(s.refs, {:mint, ref}), :ref_used),
         :ok <- approved(s, :mint, account, amount, ref, approvals),
         dest = State.account(s, account),
         :ok <- check(dest.balance + amount <= State.max_u64(), :overflow),
         :ok <- check(s.minted + amount <= State.max_u64(), :overflow) do
      s1 = State.put_account(s, account, %{dest | balance: dest.balance + amount})
      {:ok, %{s1 | minted: s.minted + amount, refs: MapSet.put(s.refs, {:mint, ref})}}
    end
  end

  defp run(s, sender, %Tx{kind: 3, payload: payload}) do
    with {:ok, {account, amount, ref, approvals}} <- issuance(payload),
         :ok <- check(account == sender, :not_sender),
         :ok <- check(amount > 0, :bad_amount),
         :ok <- check(not MapSet.member?(s.refs, {:burn, ref}), :ref_used),
         :ok <- approved(s, :burn, account, amount, ref, approvals),
         from = State.account(s, account),
         :ok <- check(from.balance >= amount, :insufficient_funds) do
      s1 = State.put_account(s, account, %{from | balance: from.balance - amount})
      {:ok, %{s1 | burned: s.burned + amount, refs: MapSet.put(s.refs, {:burn, ref})}}
    end
  end

  # --- atestado de reserva: M emissores publicam o total em reais -----------

  defp run(s, sender, %Tx{kind: kind, payload: payload}) when kind in 5..13,
    do: Assets.run(s, sender, kind, payload)

  defp run(s, sender, %Tx{kind: kind, payload: payload}) when kind in 14..19,
    do: Credentials.run(s, sender, kind, payload)

  defp run(s, _sender, %Tx{kind: 4, payload: payload}) do
    with {:ok, [seq, reserve, ref, approvals]} <-
           decode(payload, [:u64, :u64, :string, {:list, :bytes}]),
         last = if(s.attestation, do: s.attestation.seq, else: 0),
         :ok <- check(seq == last + 1, :bad_sequence),
         doc = Tx.attestation_doc(s.params.chain_id, seq, reserve, ref),
         :ok <- approved_doc(s, doc, approvals) do
      {:ok, %{s | attestation: %{seq: seq, reserve: reserve, ref: ref}}}
    end
  end

  defp issuance(payload) do
    case decode(payload, [{:fixed, 32}, :u64, :string, {:list, :bytes}]) do
      {:ok, [account, amount, ref, approvals]} -> {:ok, {account, amount, ref, approvals}}
      err -> err
    end
  end

  defp approved(%State{params: p} = s, kind, account, amount, ref, approvals) do
    approved_doc(s, Tx.issuance_doc(kind, p.chain_id, account, amount, ref), approvals)
  end

  defp approved_doc(%State{params: p}, doc, approvals) do
    check(Approvals.enough?(doc, approvals, p.issuers, p.threshold), :not_enough_approvals)
  end

  # --- util ---------------------------------------------------------------

  defp decode(payload, schema) do
    case Encoding.decode(schema, payload) do
      {:ok, v} -> {:ok, v}
      _ -> {:error, :bad_payload}
    end
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}

  @doc "Endereço (32 bytes) de uma chave pública."
  @spec address(<<_::256>>) :: <<_::256>>
  def address(pub), do: Address.hash(pub)
end
