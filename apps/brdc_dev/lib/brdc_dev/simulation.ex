defmodule BrdcDev.Simulation do
  @moduledoc """
  Cenário completo da **produção da moeda** (ciclo de uma stablecoin lastreada em reais), de ponta a ponta e
  conferindo as regras no fim. Só desenvolvimento: usa as chaves de teste de `net/` e duas carteiras de teste
  (`sim-alice` e `sim-bob`), contra um nó que já esteja rodando.

  Passos: (1) o banco recebe R$ 1.000 e os emissores **atestam a reserva**; (2) os emissores **emitem** 1.000 BRDC
  para a Alice (mint, 2 de 2); (3) prova de M-de-N: um mint com **um só** emissor é **recusado**; (4) a Alice paga
  250 à Bob; (5) a Bob **resgata** 250 (burn); (6) o banco paga R$ 250 à Bob e os emissores **reduzem a reserva**.

  Ao fim confere: a oferta cresceu 750; a reserva atestada cresceu 750; a cobertura não piorou (reserva ≥ oferta,
  se estava assim); emitido e queimado variaram 1.000 e 250; a Bob ficou com zero e a Alice com 750 menos a taxa.
  """
  alias BrdcDev.{Chain, Issuance, Wallets}
  alias BrdcLedger.{Amount, Tx}
  alias BrdcNode.Client

  @unit 1_000_000
  @deposit 1_000 * @unit
  @payment 250 * @unit

  @doc """
  Roda o cenário. `out` recebe cada linha de relatório. Devolve `{:ok, relatório}` ou `{:error, falhas}` (lista de
  textos com o que não bateu).
  """
  @spec issuance(Chain.endpoint(), map(), Path.t(), (String.t() -> any())) ::
          {:ok, map()} | {:error, [String.t()]}
  def issuance(endpoint, devnet, net_dir, out \\ &IO.puts/1) do
    with {:ok, alice} <- Wallets.ensure(net_dir, "sim-alice"),
         {:ok, bob} <- Wallets.ensure(net_dir, "sim-bob"),
         {:ok, start} <- Client.supply(endpoint),
         {:ok, a0} <- balance(endpoint, alice),
         {:ok, b0} <- balance(endpoint, bob) do
      run(endpoint, devnet, %{alice: alice, bob: bob, start: start, a0: a0, b0: b0}, out)
    else
      {:error, reason} -> {:error, ["não consegui preparar o cenário: #{inspect(reason)}"]}
    end
  end

  defp run(endpoint, devnet, ctx, out) do
    %{alice: alice, bob: bob, start: start} = ctx
    tag = Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
    prev_reserve = if start.attestation, do: start.attestation.reserve, else: start.supply
    ah = Wallets.hash({:wallet, alice})
    bh = Wallets.hash({:wallet, bob})

    out.("== Produção da moeda: ciclo de emissão e resgate (rede #{devnet.genesis.chain_id}) ==")
    show(out, "Situação inicial", start)

    out.("\n1) O banco recebe R$ #{reais(@deposit)} em depósito; os emissores ATESTAM a reserva")

    included!(
      endpoint,
      Issuance.attest(endpoint, devnet, prev_reserve + @deposit, "sim-#{tag}-deposito")
    )

    show(out, "   depois do atestado", fetch!(endpoint))

    out.("\n2) Os emissores (2 de 2) EMITEM #{brdc(@deposit)} BRDC para a Alice")
    included!(endpoint, Issuance.mint(endpoint, devnet, ah, @deposit, "sim-#{tag}-mint"))
    show(out, "   depois da emissão", fetch!(endpoint))

    out.("\n3) Prova de M-de-N: um mint com UM só emissor precisa ser recusado")

    refused =
      refused?(Issuance.mint_with(endpoint, devnet, ah, @unit, "sim-#{tag}-sozinho", ["i1"]))

    out.("   #{if refused, do: "recusado, como deve ser", else: "ACEITO (isto é um erro)"}")

    out.("\n4) A Alice paga #{brdc(@payment)} BRDC à Bob")
    pay_payload = Tx.transfer_payload(bh, @payment)

    {:ok, sent} =
      Chain.send_tx(endpoint, alice.account.seed, Tx.transfer_kind(), pay_payload, :min)

    :ok = Chain.await_included(endpoint, ah, sent.nonce)
    {:ok, a1} = balance(endpoint, alice)
    {:ok, b1} = balance(endpoint, bob)
    out.("   Alice #{brdc(a1)} · Bob #{brdc(b1)} (a taxa vai aos validadores; a oferta não muda)")

    out.("\n5) A Bob RESGATA #{brdc(@payment)} BRDC (queima, aprovada pelos emissores)")

    included!(
      endpoint,
      Issuance.burn(endpoint, devnet, bob.account.seed, @payment, "sim-#{tag}-resgate")
    )

    show(out, "   depois do resgate", fetch!(endpoint))

    out.("\n6) O banco paga R$ #{reais(@payment)} à Bob; os emissores REDUZEM a reserva atestada")

    included!(
      endpoint,
      Issuance.attest(
        endpoint,
        devnet,
        prev_reserve + @deposit - @payment,
        "sim-#{tag}-pagamento"
      )
    )

    final = fetch!(endpoint)
    show(out, "   situação final", final)
    {:ok, a2} = balance(endpoint, alice)
    {:ok, b2} = balance(endpoint, bob)

    failures = check(ctx, final, refused, a2, b2)
    report(out, failures, %{final: final, alice: a2, bob: b2})
  end

  # --- conferência das regras ---------------------------------------------------------------------

  defp check(%{start: s, a0: a0, b0: b0}, final, refused, a2, b2) do
    started_covered = match?({:covered, _}, s.coverage) or s.coverage == :none

    [
      {refused, "um mint com só 1 emissor foi aceito (M-de-N não vale)"},
      {final.supply - s.supply == @deposit - @payment,
       "a oferta deveria ter crescido #{brdc(@deposit - @payment)}, cresceu #{brdc(final.supply - s.supply)}"},
      {final.minted - s.minted == @deposit, "emitido deveria ter variado #{brdc(@deposit)}"},
      {final.burned - s.burned == @payment, "queimado deveria ter variado #{brdc(@payment)}"},
      {final.attestation != nil and
         final.attestation.reserve - ((s.attestation && s.attestation.reserve) || s.supply) ==
           @deposit - @payment,
       "a reserva atestada deveria ter crescido #{brdc(@deposit - @payment)}"},
      {not started_covered or match?({:covered, _}, final.coverage),
       "a cobertura piorou: a reserva ficou abaixo do que circula"},
      {b2 == b0,
       "a Bob deveria ter terminado com o saldo de antes (#{brdc(b0)}), tem #{brdc(b2)}"},
      {a2 < a0 + @deposit - @payment and a2 > a0 + @deposit - @payment - 100_000,
       "a Alice deveria ter #{brdc(@deposit - @payment)} a mais menos a taxa, tem #{brdc(a2 - a0)}"}
    ]
    |> Enum.reject(fn {ok?, _} -> ok? end)
    |> Enum.map(&elem(&1, 1))
  end

  defp report(out, [], data) do
    out.(
      "\n== Conferência ==\n  ok: oferta, reserva, emitido, queimado, cobertura e saldos batem com as regras"
    )

    {:ok, data}
  end

  defp report(out, failures, _data) do
    out.("\n== Conferência ==")
    Enum.each(failures, &out.("  FALHOU: #{&1}"))
    {:error, failures}
  end

  # --- util ---------------------------------------------------------------------------------------

  defp refused?({:error, _}), do: true
  defp refused?({:ok, _}), do: false

  defp included!(endpoint, {:ok, sent}) do
    :ok = Chain.await_included(endpoint, sent.sender, sent.nonce)
  end

  defp included!(_endpoint, {:error, reason}),
    do: raise("a rede recusou o passo: #{inspect(reason)}")

  defp fetch!(endpoint) do
    {:ok, s} = Client.supply(endpoint)
    s
  end

  defp balance(endpoint, wallet), do: Chain.balance(endpoint, Wallets.hash({:wallet, wallet}))

  defp show(out, title, s) do
    out.(
      "#{title}: em circulação #{brdc(s.supply)} · emitido #{brdc(s.minted)} · queimado #{brdc(s.burned)} · reserva #{reserve(s)} · cobertura #{coverage(s.coverage)}"
    )
  end

  defp reserve(%{attestation: nil}), do: "(sem atestado)"
  defp reserve(%{attestation: a}), do: "R$ #{reais(a.reserve)} (atestado #{a.seq})"

  @doc "Texto da cobertura: reserva menos o que circula (só informação, ADR-0009)."
  @spec coverage(:none | {:covered | :under, integer()}) :: String.t()
  def coverage(:none), do: "sem atestado"
  def coverage({:covered, 0}), do: "exata (reserva = oferta)"
  def coverage({:covered, margin}), do: "coberta, sobra R$ #{reais(margin)}"
  def coverage({:under, gap}), do: "ABAIXO: faltam R$ #{reais(gap)}"

  defp brdc(units), do: Amount.brdc(units)
  defp reais(units), do: Amount.brdc(units)
end
