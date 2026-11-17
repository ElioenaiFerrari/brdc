defmodule BrdcWebWeb.WalletLive do
  @moduledoc """
  Tela da carteira (Fase 6B). O servidor só sabe duas coisas: **o endereço** (público) quando a carteira é
  destravada e que ela foi **bloqueada**. Frase, passphrase e senha ficam no navegador
  (`assets/js/vault_hook.js`); nenhum evento as carrega, e qualquer parâmetro desconhecido é ignorado.
  """
  use BrdcWebWeb, :live_view
  alias BrdcCrypto.Address

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, address: nil, page_title: "Carteira")}
  end

  @impl true
  def handle_event("wallet:unlocked", %{"address" => address}, socket) when is_binary(address) do
    case Address.decode(address) do
      {:ok, _hash} -> {:noreply, assign(socket, address: address)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("wallet:locked", _params, socket), do: {:noreply, assign(socket, address: nil)}

  # qualquer outra coisa (inclusive parâmetros inesperados) é ignorada: nunca guardamos o que não conhecemos
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <.vault_panel />

        <section :if={@address} aria-label="Resumo da carteira" class="space-y-6">
          <div class="brdc-card-glow p-6">
            <p class="text-sm text-[var(--brdc-muted)]">Saldo</p>
            <p class="mt-2"><.amount units={0} class="text-5xl" unit="BRDC" /></p>
            <div class="mt-4 flex flex-wrap gap-2">
              <.chip tone={:yellow} icon="hero-scale">1 BRDC = R$ 1,00</.chip>
              <.chip icon="hero-signal-slash">Sem conexão com a rede</.chip>
            </div>
          </div>

          <div class="brdc-card p-5">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold">Seu endereço</h2>
              <.chip tone={:green} icon="hero-lock-open">Destravada</.chip>
            </div>
            <p id="my-address" class="mt-3 break-all font-mono text-sm">{@address}</p>
            <p class="mt-2 text-xs text-[var(--brdc-muted)]">
              Pode compartilhar este endereço para receber BRDC. Ele não revela sua frase.
            </p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <button
              type="button"
              phx-click={JS.dispatch("brdc:copy", to: "#vault")}
              class="brdc-btn-ghost"
            >
              <.icon name="hero-clipboard" class="size-5" /> Copiar endereço
            </button>
            <button
              type="button"
              phx-click={JS.dispatch("brdc:lock", to: "#vault")}
              class="brdc-btn-primary"
            >
              <.icon name="hero-lock-closed" class="size-5" /> Bloquear
            </button>
          </div>
          <p class="text-center text-xs text-[var(--brdc-muted)]">
            A carteira bloqueia sozinha depois de 5 minutos sem uso e ao sair da aba.
          </p>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
