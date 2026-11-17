defmodule BrdcWebWeb.VaultComponents do
  @moduledoc """
  Marcação estática do painel da carteira (criar, importar, destravar). **Nenhum segredo passa por aqui**:
  são só telas vazias; o JavaScript (`assets/js/vault_hook.js`) preenche e lê os campos no navegador. Nenhum
  campo tem `phx-change` ou `phx-submit`, então o LiveView nunca enxerga frase, passphrase nem senha.
  """
  use Phoenix.Component

  attr :id, :string, default: "vault"

  def vault_panel(assigns) do
    ~H"""
    <section
      id={@id}
      phx-hook="Vault"
      phx-update="ignore"
      aria-label="Sua carteira"
      class="brdc-card space-y-5 p-6"
    >
      <div data-view="loading">
        <p class="text-[var(--brdc-muted)]">Abrindo a carteira…</p>
      </div>

      <div data-view="unsupported" hidden class="space-y-3">
        <h2 class="text-xl font-bold">Navegador sem suporte</h2>
        <p class="text-[var(--brdc-muted)]">
          A carteira precisa de Ed25519 no navegador (Chrome 137, Firefox 129 ou Safari 17, ou mais novos)
          e de uma conexão segura (HTTPS ou localhost). Atualize o navegador para continuar.
        </p>
      </div>

      <div data-view="welcome" hidden class="space-y-5">
        <div>
          <h2 class="text-2xl font-bold">Sua carteira</h2>
          <p class="mt-2 text-[var(--brdc-muted)]">
            Só você guarda as chaves. A frase nasce neste navegador e nunca vai para o servidor.
          </p>
        </div>
        <button type="button" data-action="start-create" class="brdc-btn-primary">Criar carteira</button>
        <button type="button" data-action="start-import" class="brdc-btn-ghost w-full">
          Já tenho uma frase
        </button>
      </div>

      <div data-view="create-words" hidden class="space-y-4">
        <h2 class="text-xl font-bold">Anote sua frase de 24 palavras</h2>
        <p class="brdc-warn">
          Quem tiver a frase fica com seus fundos. Anote no papel, na ordem, e guarde longe de telas e da
          nuvem. Não tire foto e não copie para o computador.
        </p>
        <ol data-role="words" class="grid grid-cols-2 gap-2"></ol>
        <label class="flex items-center gap-3 text-sm">
          <input type="checkbox" data-role="wrote" class="size-5 accent-[#00a651]" />
          Anotei as 24 palavras, na ordem.
        </label>
        <button
          type="button"
          data-action="words-next"
          data-keep-disabled="1"
          disabled
          class="brdc-btn-primary disabled:opacity-40"
        >
          Continuar
        </button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>

      <div data-view="create-confirm" hidden class="space-y-4">
        <h2 class="text-xl font-bold">Confira a anotação</h2>
        <p class="text-[var(--brdc-muted)]">
          Digite as palavras pedidas. Assim sabemos que você anotou certo.
        </p>
        <div data-role="confirm-fields" class="space-y-3"></div>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="confirm-next" class="brdc-btn-primary">Continuar</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </div>

      <form data-view="create-secure" hidden class="space-y-4" autocomplete="off">
        <h2 class="text-xl font-bold">Proteja neste navegador</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Senha local (12 caracteres ou mais)
          <input
            type="password"
            data-role="password"
            autocomplete="new-password"
            class="brdc-input mt-1"
          />
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Repita a senha local
          <input
            type="password"
            data-role="password2"
            autocomplete="new-password"
            class="brdc-input mt-1"
          />
        </label>
        <details class="brdc-inset p-4">
          <summary class="cursor-pointer font-semibold">
            Passphrase (opcional, mais segurança)
          </summary>
          <p class="mt-2 text-sm text-[var(--brdc-muted)]">
            É uma 25ª palavra que muda a carteira inteira. Ela <strong>não fica guardada</strong>: você a
            digita toda vez que destravar. Se esquecer, os fundos ficam inacessíveis.
          </p>
          <input type="password" data-role="passphrase" autocomplete="off" class="brdc-input mt-3" />
        </details>
        <p class="text-sm text-[var(--brdc-muted)]">
          A senha local protege o cofre deste navegador; ela não recupera a carteira. A frase recupera.
        </p>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="create-submit" class="brdc-btn-primary">Criar carteira</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </form>

      <form data-view="import" hidden class="space-y-4" autocomplete="off">
        <h2 class="text-xl font-bold">Importar frase</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Frase (12 a 24 palavras) <textarea
            data-role="mnemonic"
            rows="3"
            autocomplete="off"
            autocapitalize="none"
            spellcheck="false"
            class="brdc-input mt-1"
          ></textarea>
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Passphrase (se você usa)
          <input type="password" data-role="passphrase" autocomplete="off" class="brdc-input mt-1" />
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Senha local (12 caracteres ou mais)
          <input
            type="password"
            data-role="password"
            autocomplete="new-password"
            class="brdc-input mt-1"
          />
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Repita a senha local
          <input
            type="password"
            data-role="password2"
            autocomplete="new-password"
            class="brdc-input mt-1"
          />
        </label>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <button type="button" data-action="import-submit" class="brdc-btn-primary">Importar</button>
        <button type="button" data-action="back" class="brdc-btn-ghost w-full">Voltar</button>
      </form>

      <form data-view="unlock" hidden class="space-y-4" autocomplete="off">
        <h2 class="text-xl font-bold">Destravar</h2>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Senha local
          <input
            type="password"
            data-role="password"
            autocomplete="current-password"
            class="brdc-input mt-1"
          />
        </label>
        <label class="block text-sm text-[var(--brdc-muted)]">
          Passphrase (se você usa)
          <input type="password" data-role="passphrase" autocomplete="off" class="brdc-input mt-1" />
        </label>
        <p data-role="error" hidden role="alert" class="brdc-alert"></p>
        <div data-role="mismatch" hidden class="space-y-3">
          <p class="brdc-warn">
            Atenção: com esta passphrase (ou sem ela) você abriu <strong>outra carteira</strong>, não a que foi
            criada neste navegador. Endereço:
            <span data-role="other-address" class="mt-1 block break-all font-mono text-xs"></span>
          </p>
          <button type="button" data-action="mismatch-continue" class="brdc-btn-ghost w-full">
            Continuar com esta carteira
          </button>
          <button type="button" data-action="mismatch-retry" class="brdc-btn-primary">Tentar de novo</button>
        </div>
        <button type="button" data-action="unlock-submit" class="brdc-btn-primary">Destravar</button>
        <details class="brdc-inset p-4">
          <summary class="cursor-pointer text-sm font-semibold">
            Apagar a carteira deste navegador
          </summary>
          <p class="mt-2 text-sm text-[var(--brdc-muted)]">
            Remove o cofre daqui. Sua frase continua valendo em qualquer outro lugar; sem ela, os fundos se
            perdem.
          </p>
          <label class="mt-3 flex items-center gap-3 text-sm">
            <input type="checkbox" data-role="erase-confirm" class="size-5 accent-[#ff6b6b]" />
            Tenho a frase anotada.
          </label>
          <button type="button" data-action="erase" class="brdc-btn-ghost mt-3 w-full">Apagar daqui</button>
        </details>
      </form>
    </section>
    """
  end
end
