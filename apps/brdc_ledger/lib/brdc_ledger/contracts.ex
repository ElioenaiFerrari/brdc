defmodule BrdcLedger.Contracts do
  @moduledoc """
  Interpretador dos contratos entre partes (Fase 5, ADR-0017). **Puro**: `(estado, remetente, tipo,
  carga) → estado'`. Os modelos são dados (`BrdcLedger.ContractTemplates`); aqui há só o motor que
  confere o estado, o ator e as condições e aplica os efeitos em ordem, tudo ou nada.

  Tipos de transação: `20` criar contrato · `21` agir (uma transição do modelo).

  Invariante: o escrow de cada contrato é parte do `state.escrow`, e contratos terminados ficam com
  escrow zero.
  """
  alias BrdcCrypto.Encoding
  alias BrdcLedger.{ContractTemplates, Params, State}

  @max_u64 0xFFFFFFFFFFFFFFFF
  @terminal [:done, :refunded, :cancelled, :closed, :repaid, :defaulted]

  @spec kinds() :: Range.t()
  def kinds, do: 20..21

  @doc "Taxa mínima: cada passo de um contrato (ADR-0014): 0,01 BRDC."
  @spec min_fee(Params.t(), 20..21) :: non_neg_integer()
  def min_fee(%Params{} = p, _kind), do: p.contract_fee

  @doc "Estados finais (sem escrow)."
  @spec terminal() :: [atom()]
  def terminal, do: @terminal

  @spec create_payload(String.t(), String.t(), binary(), [non_neg_integer()]) :: binary()
  def create_payload(template, id, party_b, terms),
    do:
      Encoding.encode([:string, :string, {:fixed, 32}, {:list, :u64}], [
        template,
        id,
        party_b,
        terms
      ])

  @spec act_payload(String.t(), String.t()) :: binary()
  def act_payload(id, action), do: Encoding.encode([:string, :string], [id, action])

  # --- criar -------------------------------------------------------------------------------

  @spec run(State.t(), <<_::256>>, 20..21, binary()) :: {:ok, State.t()} | {:error, atom()}
  def run(s, sender, 20, payload) do
    with {:ok, [template_id, id, party_b, values]} <-
           decode(payload, [:string, :string, {:fixed, 32}, {:list, :u64}]),
         {:ok, template} <- fetch(ContractTemplates.all(), template_id, :no_template),
         :ok <- check(id_ok?(id), :bad_id),
         :ok <- check(not Map.has_key?(s.contracts, id), :contract_exists),
         :ok <- check(party_b != sender, :self_deal),
         {:ok, terms} <- build_terms(s, template_id, template, values) do
      contract = %{
        template: template_id,
        a: sender,
        b: party_b,
        terms: terms,
        state: template.initial.state,
        escrow: 0,
        vars: %{}
      }

      with {:ok, s2, c2} <- apply_effects(template.initial.effects, s, contract) do
        {:ok, %{s2 | contracts: Map.put(s2.contracts, id, c2)}}
      end
    end
  end

  # --- agir ----------------------------------------------------------------------------------

  def run(s, sender, 21, payload) do
    with {:ok, [id, action]} <- decode(payload, [:string, :string]),
         {:ok, c} <- fetch(s.contracts, id, :no_contract),
         {:ok, template} <- fetch(ContractTemplates.all(), c.template, :no_template),
         {:ok, tr} <- fetch(template.transitions, action, :no_transition),
         :ok <- check(c.state == tr.from, :bad_state),
         :ok <- check_actor(tr.actor, sender, c),
         :ok <- check_guards(Map.get(tr, :guards, []), s, c),
         {:ok, s2, c2} <- apply_effects(tr.effects, s, c) do
      {:ok, %{s2 | contracts: Map.put(s2.contracts, id, %{c2 | state: tr.to})}}
    end
  end

  # --- termos ----------------------------------------------------------------------------------

  defp build_terms(s, id, template, values) do
    with :ok <- check(length(values) == length(template.terms), :bad_terms),
         terms = template.terms |> Enum.zip(values) |> Map.new(),
         :ok <- check(sane_terms?(s, id, terms), :bad_terms) do
      {:ok, terms}
    end
  end

  defp sane_terms?(s, "compra-venda", t), do: t.price > 0 and window?(s, t.duration)

  defp sane_terms?(s, "emprestimo", t),
    do: t.principal > 0 and t.repay > 0 and window?(s, t.duration)

  defp sane_terms?(s, "aluguel", t) do
    t.rent > 0 and t.periods in 1..1200 and
      t.period in s.params.min_window..s.params.max_window//1 and
      t.grace <= s.params.max_window and t.rent * t.periods <= @max_u64 and
      t.deposit <= @max_u64
  end

  defp window?(s, secs), do: secs in s.params.min_window..s.params.max_window//1

  # --- atores e condições ------------------------------------------------------------------------

  defp check_actor(:any, _sender, _c), do: :ok
  defp check_actor(:a, sender, c), do: check(sender == c.a, :not_party)
  defp check_actor(:b, sender, c), do: check(sender == c.b, :not_party)

  defp check_guards(guards, s, c) do
    Enum.reduce_while(guards, :ok, fn g, :ok ->
      case guard(g, s, c) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp guard({:before, var}, s, c), do: check(s.time < Map.get(c.vars, var, 0), :too_late)
  defp guard({:at_or_after, var}, s, c), do: check(s.time >= Map.get(c.vars, var, 0), :too_early)

  defp guard({:var_lt_term, var, term}, _s, c),
    do: check(Map.get(c.vars, var, 0) < c.terms[term], :not_ready)

  defp guard({:var_eq_term, var, term}, _s, c),
    do: check(Map.get(c.vars, var, 0) == c.terms[term], :not_ready)

  # --- efeitos (em ordem; qualquer falha desfaz tudo porque o estado é imutável) --------------------

  defp apply_effects(effects, s, c) do
    Enum.reduce_while(effects, {:ok, s, c}, fn effect, {:ok, s, c} ->
      case effect(effect, s, c) do
        {:ok, s2, c2} -> {:cont, {:ok, s2, c2}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp effect({:lock, party, expr}, s, c) do
    amount = eval(expr, s, c)
    addr = addr(c, party)
    acc = State.account(s, addr)

    if acc.balance >= amount do
      s2 = State.put_account(s, addr, %{acc | balance: acc.balance - amount})
      {:ok, %{s2 | escrow: s2.escrow + amount}, %{c | escrow: c.escrow + amount}}
    else
      {:error, :insufficient_funds}
    end
  end

  defp effect({:release, party, expr}, s, c) do
    amount = min(eval(expr, s, c), c.escrow)
    credit(s, c, party, amount, :escrow)
  end

  defp effect({:pay, from, to, expr}, s, c) do
    amount = eval(expr, s, c)
    payer = State.account(s, addr(c, from))

    if payer.balance >= amount do
      s2 = State.put_account(s, addr(c, from), %{payer | balance: payer.balance - amount})
      credit(s2, c, to, amount, :direct)
    else
      {:error, :insufficient_funds}
    end
  end

  defp effect({:set_var, var, expr}, s, c),
    do: {:ok, s, %{c | vars: Map.put(c.vars, var, eval(expr, s, c))}}

  defp effect({:inc_var, var}, s, c),
    do: {:ok, s, %{c | vars: Map.update(c.vars, var, 1, &(&1 + 1))}}

  # `:escrow` tira do escrow; `:direct` o dinheiro já saiu da conta de quem paga
  defp credit(s, c, party, amount, source) do
    addr = addr(c, party)
    acc = State.account(s, addr)

    if acc.balance + amount > @max_u64 do
      {:error, :overflow}
    else
      s2 = State.put_account(s, addr, %{acc | balance: acc.balance + amount})

      case source do
        :escrow -> {:ok, %{s2 | escrow: s2.escrow - amount}, %{c | escrow: c.escrow - amount}}
        :direct -> {:ok, s2, c}
      end
    end
  end

  defp addr(c, :a), do: c.a
  defp addr(c, :b), do: c.b

  # --- expressões ---------------------------------------------------------------------------------

  defp eval({:term, k}, _s, c), do: Map.fetch!(c.terms, k)
  defp eval({:var, k}, _s, c), do: Map.get(c.vars, k, 0)
  defp eval({:const, n}, _s, _c), do: n
  defp eval(:time, s, _c), do: s.time
  defp eval(:escrow, _s, c), do: c.escrow
  defp eval({:add, a, b}, s, c), do: eval(a, s, c) + eval(b, s, c)
  defp eval({:sub, a, b}, s, c), do: max(eval(a, s, c) - eval(b, s, c), 0)
  defp eval({:mul, a, b}, s, c), do: eval(a, s, c) * eval(b, s, c)
  defp eval({:min, a, b}, s, c), do: min(eval(a, s, c), eval(b, s, c))

  # --- util -----------------------------------------------------------------------------------------

  defp id_ok?(id), do: byte_size(id) in 1..64 and String.printable?(id)

  defp fetch(map, key, reason) do
    case Map.fetch(map, key) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, reason}
    end
  end

  defp decode(payload, schema) do
    case Encoding.decode(schema, payload) do
      {:ok, v} -> {:ok, v}
      _ -> {:error, :bad_payload}
    end
  end

  defp check(true, _), do: :ok
  defp check(false, reason), do: {:error, reason}
end
