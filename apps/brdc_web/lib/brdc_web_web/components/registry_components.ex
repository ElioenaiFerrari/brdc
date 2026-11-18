defmodule BrdcWebWeb.RegistryComponents do
  @moduledoc """
  Painéis de credenciais (do titular) e do órgão (propor, assinar e emitir). Marcação estática: as listas, a
  leitura do que será assinado e a assinatura acontecem no navegador (`assets/js/registry_hook.js`). Nenhum
  campo tem `phx-change` ou `phx-submit`.
  """
  use Phoenix.Component

  def credentials_panel(assigns) do
    ~H"""
    <section
      id="credentials"
      phx-hook="Credentials"
      phx-update="ignore"
      aria-label="Credenciais"
      class="brdc-card space-y-4 p-5"
    >
      <div data-step="list" class="space-y-4">
        <h2 class="text-lg font-bold">Credenciais</h2>
        <p data-role="empty" class="text-sm text-[var(--brdc-muted)]">
          Você ainda não tem credenciais. Quando um órgão emitir uma para o seu endereço, ela aparece aqui e
          fica pendente durante a janela de contestação.
        </p>
        <ul data-role="list" class="space-y-3"></ul>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
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
            <dt class="text-[var(--brdc-muted)]">Credencial</dt><dd data-role="r-cred"></dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">O que acontece</dt><dd data-role="r-effect"></dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Taxa da rede</dt><dd data-role="r-fee"></dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Rede</dt><dd data-role="r-chain"></dd>
          </div>
        </dl>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="confirm" class="brdc-btn-primary">Assinar e enviar</button>
        <button type="button" data-action="cancel" class="brdc-btn-ghost w-full">Cancelar</button>
      </div>
      <div data-step="done" hidden class="space-y-3">
        <h2 class="text-lg font-bold">Enviado</h2>
        <p class="text-sm text-[var(--brdc-muted)]">
          Entra no próximo bloco. Id:
          <span data-role="txid" class="mt-1 block break-all font-mono text-xs"></span>
        </p>
        <button type="button" data-action="cancel" class="brdc-btn-ghost w-full">Voltar</button>
      </div>
    </section>
    """
  end

  def organ_panel(assigns) do
    ~H"""
    <section
      id="organ"
      phx-hook="Organ"
      phx-update="ignore"
      aria-label="Órgão"
      class="brdc-card space-y-4 p-5"
      hidden
    >
      <div data-step="list" class="space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-lg font-bold">Órgão: assinaturas</h2>
          <button type="button" data-action="new" class="brdc-chip brdc-chip-blue cursor-pointer">Nova ação</button>
        </div>
        <p class="text-sm text-[var(--brdc-muted)]">
          Você faz parte do órgão de: <span data-role="types" class="font-semibold"></span>. Emitir exige várias
          assinaturas, cada uma na carteira de um membro.
        </p>
        <p data-role="empty" class="text-sm text-[var(--brdc-muted)]">
          Nenhuma emissão esperando assinatura.
        </p>
        <ul data-role="list" class="space-y-3"></ul>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
      </div>

      <div data-step="new" hidden class="space-y-4">
        <h2 class="text-lg font-bold">Nova ação do órgão</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          O que você quer fazer <select data-role="action" class="brdc-input mt-1"></select>
        </label>
        <div data-role="form" class="space-y-4"></div>
        <p class="brdc-warn">
          A ação só vale depois que o número de membros exigido pela classe ou pelo tipo assinar, cada um na
          própria carteira.
        </p>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="propose" class="brdc-btn-primary">Propor aos outros membros</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>

      <div data-step="review" hidden class="space-y-4">
        <h2 class="text-lg font-bold" data-role="review-title">Confira antes de assinar</h2>
        <div data-role="review-lines" class="brdc-inset space-y-2 p-4 text-sm"></div>
        <p class="brdc-warn">
          Assine só o que você entende e aprova. Sua assinatura é definitiva para esta emissão.
        </p>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="confirm" class="brdc-btn-primary" data-role="confirm-label">Assinar</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Cancelar</button>
      </div>

      <div data-step="done" hidden class="space-y-3">
        <h2 class="text-lg font-bold" data-role="done-title">Pronto</h2>
        <p data-role="done-text" class="text-sm text-[var(--brdc-muted)]"></p>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>
    </section>
    """
  end

  def assets_panel(assigns) do
    ~H"""
    <section
      id="assets"
      phx-hook="Assets"
      phx-update="ignore"
      aria-label="Bens"
      class="brdc-card space-y-4 p-5"
      hidden
    >
      <div data-step="list" class="space-y-4">
        <h2 class="text-lg font-bold">Bens</h2>
        <p class="text-sm text-[var(--brdc-muted)]">
          Bens registrados em seu nome ou que você está comprando. O registro e o veto são do órgão da classe;
          a venda entre pessoas retém o dinheiro na rede até o fim da janela de veto.
        </p>
        <ul data-role="list" class="space-y-3"></ul>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
      </div>

      <div data-step="offer" hidden class="space-y-4">
        <h2 class="text-lg font-bold" data-role="offer-title">Oferecer à venda</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Comprador (endereço brdc1…)
          <input
            type="text"
            data-role="buyer"
            autocomplete="off"
            autocapitalize="none"
            spellcheck="false"
            class="brdc-input mt-1 font-mono text-sm"
          />
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Preço em BRDC
          <input
            type="text"
            data-role="price"
            data-money
            inputmode="decimal"
            autocomplete="off"
            placeholder="0,00"
            class="brdc-input mt-1"
          />
        </label>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="offer-review" class="brdc-btn-primary">Revisar</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>

      <div data-step="review" hidden class="space-y-4">
        <h2 class="text-lg font-bold">Confira antes de assinar</h2>
        <div data-role="review-lines" class="brdc-inset space-y-3 p-4 text-sm"></div>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="confirm" class="brdc-btn-primary">Assinar e enviar</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Cancelar</button>
      </div>

      <div data-step="done" hidden class="space-y-3">
        <h2 class="text-lg font-bold">Enviado</h2>
        <p class="text-sm text-[var(--brdc-muted)]">
          Entra no próximo bloco. Id:
          <span data-role="txid" class="mt-1 block break-all font-mono text-xs"></span>
        </p>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>
    </section>
    """
  end
end
