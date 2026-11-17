defmodule BrdcWebWeb.WalletLive do
  @moduledoc """
  Tela da carteira (Fase 6). O servidor sabe: **o endereço** (público), que a carteira foi bloqueada, e
  repassa ao nó a transação **já assinada** que o navegador entrega. Frase, passphrase e senha ficam no
  navegador (`assets/js/vault_hook.js`); nenhum evento as carrega, e parâmetros desconhecidos são ignorados.

  Eventos aceitos: `wallet:unlocked` (endereço), `wallet:locked`, `wallet:prepare` (responde com os dados
  públicos da rede e da conta para o navegador montar a transação) e `wallet:submit` (transação em hexadecimal).
  """
  use BrdcWebWeb, :live_view
  alias BrdcCrypto.Address
  alias BrdcLedger.Amount
  alias BrdcLedger.Tx
  alias BrdcWebWeb.Wallet.Chain

  @fast_ms 1_000
  @slow_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       address: nil,
       chain: nil,
       offline: false,
       awaiting: false,
       contracts_sent: nil,
       page_title: "Carteira"
     )}
  end

  @impl true
  def handle_event("wallet:unlocked", %{"address" => address}, socket) when is_binary(address) do
    case Address.decode(address) do
      {:ok, _hash} ->
        socket = assign(socket, address: address)
        send(self(), :refresh)
        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("wallet:locked", _params, socket) do
    {:noreply,
     assign(socket,
       address: nil,
       chain: nil,
       offline: false,
       awaiting: false,
       contracts_sent: nil
     )}
  end

  # dados PÚBLICOS para o navegador montar e mostrar a transação (números como texto: vão a 2^64 - 1)
  def handle_event("wallet:prepare", _params, %{assigns: %{address: address}} = socket)
      when is_binary(address) do
    case Chain.snapshot(address) do
      {:ok, c} ->
        {:reply,
         %{
           ok: true,
           chain_id: c.chain_id,
           nonce: Integer.to_string(c.pending_nonce),
           balance: Integer.to_string(c.pending_balance),
           transfer_base: Integer.to_string(c.transfer_base),
           per_byte: Integer.to_string(c.per_byte),
           contract_fee: Integer.to_string(c.contract_fee)
         }, assign(socket, chain: c, offline: false)}

      {:error, :offline} ->
        {:reply, %{ok: false, error: "offline"}, assign(socket, offline: true)}
    end
  end

  def handle_event("wallet:submit", %{"tx" => hex}, %{assigns: %{address: address}} = socket)
      when is_binary(hex) and is_binary(address) do
    with {:ok, bin} <- Base.decode16(hex, case: :mixed),
         {:ok, %Tx{} = tx} <- Tx.decode(bin),
         true <- Address.from_public_key(tx.sender_pub) == address,
         {:ok, id} <- Chain.submit(bin) do
      send(self(), :refresh)
      {:reply, %{ok: true, id: Base.encode16(id, case: :lower)}, assign(socket, awaiting: true)}
    else
      false ->
        {:reply, %{ok: false, error: "not_your_address"}, socket}

      {:error, reason} when is_atom(reason) ->
        {:reply, %{ok: false, error: Atom.to_string(reason)}, socket}

      _ ->
        {:reply, %{ok: false, error: "malformed"}, socket}
    end
  end

  # qualquer outra coisa (inclusive parâmetros inesperados) é ignorada: nunca guardamos o que não conhecemos
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:refresh, %{assigns: %{address: address}} = socket) when is_binary(address) do
    {chain, offline} = load_chain(address)
    Process.send_after(self(), :refresh, refresh_delay(chain))
    socket = assign(socket, chain: chain, offline: offline, awaiting: awaiting?(socket, chain))
    {:noreply, push_contracts(socket, address, chain)}
  end

  def handle_info(:refresh, socket), do: {:noreply, socket}

  # manda os contratos ao navegador só quando mudam (ou o horário do bloco muda, por causa dos prazos)
  defp push_contracts(socket, _address, nil), do: socket

  defp push_contracts(socket, address, chain) do
    case Chain.contracts(address) do
      {:ok, list} ->
        payload = %{contracts: list, time: Integer.to_string(chain.time), address: address}

        if payload == socket.assigns.contracts_sent,
          do: socket,
          else: socket |> assign(contracts_sent: payload) |> push_event("contracts", payload)

      {:error, _} ->
        socket
    end
  end

  defp load_chain(address) do
    case Chain.snapshot(address) do
      {:ok, c} -> {c, false}
      {:error, :offline} -> {nil, true}
    end
  end

  # rápido enquanto há transação pendente (o bloco sai logo), devagar no resto
  defp refresh_delay(%{pending: p}) when p > 0, do: @fast_ms
  defp refresh_delay(_), do: @slow_ms

  defp awaiting?(_socket, %{pending: 0}), do: false
  defp awaiting?(socket, _chain), do: socket.assigns.awaiting

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <.vault_panel />

        <section :if={@address} aria-label="Resumo da carteira" class="space-y-6">
          <div class="brdc-card-glow p-6">
            <p class="text-sm text-[var(--brdc-muted)]">Saldo</p>
            <p class="mt-2">
              <.amount units={(@chain && @chain.balance) || 0} class="text-5xl" unit="BRDC" />
            </p>
            <p
              :if={@chain && @chain.pending_balance != @chain.balance}
              class="mt-2 text-sm text-[var(--brdc-yellow)]"
            >
              Com as transações pendentes: {Amount.brdc(@chain.pending_balance)} BRDC
            </p>
            <div class="mt-4 flex flex-wrap gap-2">
              <.chip tone={:yellow} icon="hero-scale">1 BRDC = R$ 1,00</.chip>
              <.chip :if={@chain} tone={:green} icon="hero-signal">
                {@chain.chain_id} · bloco {@chain.height}
              </.chip>
              <.chip :if={!@chain} icon="hero-signal-slash">
                {if @offline, do: "Sem conexão com a rede", else: "Conectando…"}
              </.chip>
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

          <.send_panel />

          <.contracts_panel />

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
