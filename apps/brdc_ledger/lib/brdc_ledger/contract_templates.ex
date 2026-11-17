defmodule BrdcLedger.ContractTemplates do
  @moduledoc """
  Modelos de contrato entre partes (Fase 5, ADR-0017) **escritos como dados**: estados, transições,
  quem age, condições de tempo e efeitos sobre o dinheiro. Quem os interpreta é
  `BrdcLedger.Contracts`, com um vocabulário **fechado**: não existe código de terceiros nem forma
  de um modelo fazer algo fora do que está listado aqui.

  Partes: `:a` (quem cria) e `:b` (a outra). `terms` são números (ordem fixa por modelo); `vars`
  guardam prazos e contadores. O "agora" é o horário do bloco (ADR-0016).

  ## Vocabulário
  - **Atores:** `:a`, `:b`, `:any`.
  - **Condições:** `{:before, var}` (agora < var), `{:at_or_after, var}` (agora >= var),
    `{:var_lt_term, var, term}`, `{:var_eq_term, var, term}`.
  - **Efeitos:** `{:lock, parte, expr}` (da conta para o escrow do contrato), `{:release, parte, expr}`
    (do escrow para a conta), `{:pay, de, para, expr}` (direto, sem escrow), `{:set_var, var, expr}`,
    `{:inc_var, var}`.
  - **Expressões:** `{:term, k}`, `{:var, k}`, `{:const, n}`, `:time`, `:escrow`, `{:add, e, e}`,
    `{:sub, e, e}` (não negativo), `{:mul, e, e}`, `{:min, e, e}`.
  """

  @type template :: %{
          terms: [atom()],
          initial: %{effects: [tuple()], state: atom()},
          transitions: %{String.t() => map()}
        }

  @templates %{
    # Compra e venda de um bem ou serviço fora da chain. O comprador deposita o preço em escrow e
    # confirma o recebimento para liberá-lo. Se o prazo vence sem confirmação, o escrow volta ao
    # comprador (sem arbitragem, o desenho protege quem pagou).
    "compra-venda" => %{
      terms: [:price, :duration],
      initial: %{state: :open, effects: []},
      transitions: %{
        "accept" => %{
          from: :open,
          actor: :b,
          effects: [
            {:lock, :b, {:term, :price}},
            {:set_var, :deadline, {:add, :time, {:term, :duration}}}
          ],
          to: :funded
        },
        "confirm" => %{
          from: :funded,
          actor: :b,
          effects: [{:release, :a, :escrow}],
          to: :done
        },
        "refund" => %{
          from: :funded,
          actor: :a,
          effects: [{:release, :b, :escrow}],
          to: :refunded
        },
        "refund_expired" => %{
          from: :funded,
          actor: :any,
          guards: [{:at_or_after, :deadline}],
          effects: [{:release, :b, :escrow}],
          to: :refunded
        },
        "cancel" => %{from: :open, actor: :a, effects: [], to: :cancelled}
      }
    },
    # Aluguel: caução em escrow, parcelas pagas direto ao locador, e liquidação ao fim do prazo.
    # A caução cobre as parcelas não pagas (até o valor da caução); o resto volta ao locatário.
    "aluguel" => %{
      terms: [:rent, :period, :periods, :deposit, :grace],
      initial: %{state: :open, effects: []},
      transitions: %{
        "accept" => %{
          from: :open,
          actor: :b,
          effects: [
            {:lock, :b, {:term, :deposit}},
            {:set_var, :paid, {:const, 0}},
            {:set_var, :settle_at,
             {:add, :time, {:add, {:mul, {:term, :period}, {:term, :periods}}, {:term, :grace}}}}
          ],
          to: :active
        },
        "pay_rent" => %{
          from: :active,
          actor: :b,
          guards: [{:var_lt_term, :paid, :periods}],
          effects: [{:pay, :b, :a, {:term, :rent}}, {:inc_var, :paid}],
          to: :active
        },
        "settle" => %{
          from: :active,
          actor: :any,
          guards: [{:at_or_after, :settle_at}],
          effects: [
            {:release, :a,
             {:min, :escrow, {:mul, {:sub, {:term, :periods}, {:var, :paid}}, {:term, :rent}}}},
            {:release, :b, :escrow}
          ],
          to: :closed
        },
        "settle_paid" => %{
          from: :active,
          actor: :a,
          guards: [{:var_eq_term, :paid, :periods}],
          effects: [{:release, :b, :escrow}],
          to: :closed
        },
        "cancel" => %{from: :open, actor: :a, effects: [], to: :cancelled}
      }
    },
    # Empréstimo simples: o credor trava o principal ao criar; o devedor aceita e recebe; devolve o
    # valor combinado (juros, se houver, já estão dentro dele). Sem garantia: o atraso só é registrado.
    "emprestimo" => %{
      terms: [:principal, :repay, :duration],
      initial: %{state: :open, effects: [{:lock, :a, {:term, :principal}}]},
      transitions: %{
        "accept" => %{
          from: :open,
          actor: :b,
          effects: [
            {:release, :b, :escrow},
            {:set_var, :deadline, {:add, :time, {:term, :duration}}}
          ],
          to: :active
        },
        "repay" => %{
          from: :active,
          actor: :b,
          effects: [{:pay, :b, :a, {:term, :repay}}],
          to: :repaid
        },
        "mark_default" => %{
          from: :active,
          actor: :any,
          guards: [{:at_or_after, :deadline}],
          effects: [],
          to: :defaulted
        },
        "cancel" => %{from: :open, actor: :a, effects: [{:release, :a, :escrow}], to: :cancelled}
      }
    }
  }

  @doc "Os modelos disponíveis, por id."
  @spec all() :: %{String.t() => template()}
  def all, do: @templates

  @doc "Um modelo pelo id."
  @spec fetch(String.t()) :: {:ok, template()} | :error
  def fetch(id), do: Map.fetch(@templates, id)
end
