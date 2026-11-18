defmodule BrdcWebWeb.SendComponents do
  @moduledoc """
  Painel de envio de BRDC. Marcação estática: a transação é montada e **assinada no navegador**
  (`assets/js/send_hook.js`), que mostra em texto claro o que será assinado antes de pedir a confirmação.
  Nenhum campo tem `phx-change` ou `phx-submit`.
  """
  use Phoenix.Component

  def send_panel(assigns) do
    ~H"""
    <section
      id="send"
      phx-hook="Send"
      phx-update="ignore"
      aria-label="Enviar BRDC"
      class="brdc-card space-y-4 p-5"
    >
      <div data-step="form" class="space-y-4">
        <h2 class="text-lg font-bold">Enviar</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Para (endereço brdc1…)
          <input
            type="text"
            data-role="to"
            autocomplete="off"
            autocapitalize="none"
            spellcheck="false"
            class="brdc-input mt-1 font-mono text-sm"
          />
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Valor em BRDC
          <input
            type="text"
            inputmode="decimal"
            data-role="amount"
            data-money
            autocomplete="off"
            placeholder="0,00"
            class="brdc-input mt-1 text-xl"
          />
        </label>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="review" class="brdc-btn-primary">Revisar</button>
      </div>

      <div data-step="review" hidden class="space-y-4">
        <h2 class="text-lg font-bold">Confira antes de assinar</h2>
        <dl class="brdc-inset space-y-3 p-4 text-sm">
          <div>
            <dt class="text-[var(--brdc-muted)]">Você envia</dt><dd
              data-role="r-amount"
              data-decrypt
              class="text-2xl font-bold"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Para</dt><dd
              data-role="r-to"
              data-decrypt
              class="break-all font-mono text-xs"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Taxa da rede</dt><dd data-role="r-fee" data-decrypt>
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Total debitado</dt><dd
              data-role="r-total"
              data-decrypt
              class="font-semibold"
            >
            </dd>
          </div>
          <div>
            <dt class="text-[var(--brdc-muted)]">Rede</dt><dd data-role="r-chain"></dd>
          </div>
        </dl>
        <p class="brdc-warn">
          Transferências na BRDC não podem ser desfeitas nem bloqueadas. Confira o endereço inteiro.
        </p>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="confirm" class="brdc-btn-primary">Assinar e enviar</button>
        <button type="button" data-action="cancel" class="brdc-btn-ghost w-full">Cancelar</button>
      </div>

      <div data-step="done" hidden class="space-y-3">
        <h2 class="text-lg font-bold">Enviada</h2>
        <p class="text-sm text-[var(--brdc-muted)]">
          A transação foi para a rede e entra no próximo bloco. Id:
          <span data-role="txid" class="mt-1 block break-all font-mono text-xs"></span>
        </p>
        <button type="button" data-action="again" class="brdc-btn-ghost w-full">Enviar outra</button>
      </div>
    </section>
    """
  end
end
