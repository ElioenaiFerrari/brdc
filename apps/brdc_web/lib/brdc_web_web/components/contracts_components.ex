defmodule BrdcWebWeb.ContractsComponents do
  @moduledoc """
  Painel de contratos entre partes. Marcação estática: a lista, a revisão e a assinatura são desenhadas no
  navegador (`assets/js/contracts_hook.js`), que recebe os contratos do servidor, calcula o que cada ação faz
  com o dinheiro e mostra **em texto claro** antes de assinar. Nenhum campo tem `phx-change` ou `phx-submit`.
  """
  use Phoenix.Component

  def contracts_panel(assigns) do
    ~H"""
    <section
      id="contracts"
      phx-hook="Contracts"
      phx-update="ignore"
      aria-label="Contratos"
      class="brdc-card space-y-4 p-5"
    >
      <div data-step="list" class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold">Contratos</h2>
          <button type="button" data-action="new" class="brdc-chip brdc-chip-blue cursor-pointer">Novo contrato</button>
        </div>
        <p data-role="empty" class="text-sm text-[var(--brdc-muted)]">
          Você ainda não tem contratos. Compra e venda, aluguel e empréstimo entre duas pessoas, com o dinheiro
          retido pela rede até as regras liberarem.
        </p>
        <ul data-role="list" class="space-y-3"></ul>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
      </div>

      <div data-step="new" hidden class="space-y-4">
        <h2 class="text-lg font-bold">Novo contrato</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Tipo <select data-role="template" class="brdc-input mt-1"></select>
        </label>
        <p data-role="template-help" class="text-sm text-[var(--brdc-muted)]"></p>
        <label class="block text-sm text-[var(--brdc-muted)]">
          <span data-role="party-label">Outra parte</span>
          (endereço brdc1…)
          <input
            type="text"
            data-role="party"
            autocomplete="off"
            autocapitalize="none"
            spellcheck="false"
            class="brdc-input mt-1 font-mono text-sm"
          />
        </label>
        <div data-role="terms" class="space-y-3"></div>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="review-new" class="brdc-btn-primary">Revisar</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>

      <div data-step="review" hidden class="space-y-4">
        <h2 class="text-lg font-bold">Confira antes de assinar</h2>
        <dl class="brdc-inset space-y-3 p-4 text-sm">
          <div>
            <dt class="text-[var(--brdc-muted)]">O que você está fazendo</dt><dd
              data-role="r-what"
              class="font-semibold"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Contrato</dt><dd data-role="r-contract"></dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Com</dt><dd
              data-role="r-party"
              class="break-all font-mono text-xs"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Condições</dt><dd
              data-role="r-terms"
              class="space-y-1"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">O dinheiro</dt><dd
              data-role="r-money"
              class="space-y-1 font-semibold"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Taxa da rede</dt><dd data-role="r-fee"></dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Rede</dt><dd data-role="r-chain"></dd>
          </div>
        </dl>
        <p class="brdc-warn">
          A rede não decide disputas: ela só executa as regras do contrato. Confira os valores e o endereço da outra parte.
        </p>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="confirm" class="brdc-btn-primary">Assinar e enviar</button>
        <button type="button" data-action="cancel" class="brdc-btn-ghost w-full">Cancelar</button>
      </div>

      <div data-step="done" hidden class="space-y-3">
        <h2 class="text-lg font-bold">Enviado</h2>
        <p class="text-sm text-[var(--brdc-muted)]">
          A transação foi para a rede e entra no próximo bloco. Id:
          <span data-role="txid" class="mt-1 block break-all font-mono text-xs"></span>
        </p>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar aos contratos</button>
      </div>
    </section>
    """
  end
end
