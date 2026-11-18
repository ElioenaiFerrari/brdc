defmodule BrdcWebWeb.ExplorerLive do
  @moduledoc """
  Explorador público e **somente leitura** da cadeia: blocos (com o certificado conferido), transações, contas e
  o que está esperando bloco. Não tem chave, não assina e não envia nada; lê pela porta pública de um nó
  (`BrdcWebWeb.Explorer.Data`). A tela se atualiza sozinha: 1 s quando há transação pendente, 3 s parado.

  Rotas: `/explorer` · `/explorer/block/:height` · `/explorer/tx/:id` · `/explorer/account/:address`.
  """
  use BrdcWebWeb, :live_view
  alias BrdcNode.Explorer
  alias BrdcWebWeb.Explorer.Data

  @fast_ms 1_000
  @slow_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, page_title: "Explorador", error: nil, data: nil, offline: false, query: "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = load(socket, socket.assigns.live_action, params)
    if connected?(socket), do: schedule(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) when is_binary(q) do
    case Data.classify(q) do
      {:block, h} ->
        {:noreply, push_patch(socket, to: ~p"/explorer/block/#{h}")}

      {:tx, id} ->
        {:noreply, push_patch(socket, to: ~p"/explorer/tx/#{Base.encode16(id, case: :lower)}")}

      {:account, addr, _} ->
        {:noreply, push_patch(socket, to: ~p"/explorer/account/#{addr}")}

      :unknown ->
        {:noreply,
         assign(socket,
           query: q,
           error: "Digite uma altura, um id de transação (64 caracteres) ou um endereço brdc1…"
         )}
    end
  end

  def handle_event("search", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:tick, socket) do
    socket = load(socket, socket.assigns.live_action, socket.assigns[:params] || %{})
    schedule(socket)
    {:noreply, socket}
  end

  defp schedule(socket) do
    pending = match?(%{status: %{pending: p}} when p > 0, socket.assigns.data)
    Process.send_after(self(), :tick, if(pending, do: @fast_ms, else: @slow_ms))
  end

  defp load(socket, action, params) do
    socket = assign(socket, params: params, error: nil)

    case fetch(action, params) do
      {:ok, data} -> assign(socket, data: data, offline: false)
      {:error, :offline} -> assign(socket, data: nil, offline: true)
      {:error, :not_found} -> assign(socket, data: nil, offline: false, error: not_found(action))
    end
  end

  defp fetch(:home, _), do: Data.overview() |> tag(:home)

  defp fetch(:block, %{"height" => h}),
    do: with({:ok, n} <- height(h), do: Data.block(n)) |> tag(:block)

  defp fetch(:tx, %{"id" => id}) do
    case Data.classify(id) do
      {:tx, bin} -> Data.tx(bin) |> tag(:tx)
      _ -> {:error, :not_found}
    end
  end

  defp fetch(:account, %{"address" => a}) do
    case Data.classify(a) do
      {:account, addr, hash} -> Data.account(addr, hash) |> tag(:account)
      _ -> {:error, :not_found}
    end
  end

  defp fetch(_, _), do: {:error, :not_found}

  defp tag({:ok, data}, kind), do: {:ok, Map.put(data, :kind, kind)}
  defp tag(other, _), do: other

  defp height(text) do
    case Integer.parse(text) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :not_found}
    end
  end

  defp not_found(:block), do: "Esse bloco não existe (ou já saiu da memória do nó)."

  defp not_found(:tx),
    do: "Não achei essa transação. Se acabou de enviar, veja as pendentes na página inicial."

  defp not_found(_), do: "Não achei o que você procurou."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-6">
        <.search query={@query} />

        <p :if={@error} role="alert" class="brdc-alert">{@error}</p>

        <section :if={@offline} class="brdc-card p-6">
          <h1 class="text-lg font-bold">Sem conexão com a rede</h1>
          <p class="mt-2 text-sm text-[var(--brdc-muted)]">
            Não consegui falar com o nó. Suba a rede de teste com <code>mix brdc.devnet.up</code>
            e recarregue.
          </p>
        </section>

        <.home :if={@data && @data.kind == :home} d={@data} />
        <.block_page :if={@data && @data.kind == :block} d={@data} />
        <.tx_page :if={@data && @data.kind == :tx} d={@data} />
        <.account_page :if={@data && @data.kind == :account} d={@data} />
      </div>
    </Layouts.app>
    """
  end

  attr :query, :string, default: ""

  defp search(assigns) do
    ~H"""
    <form
      phx-submit="search"
      class="grid grid-cols-[1fr_auto] gap-2"
      role="search"
      aria-label="Buscar na cadeia"
    >
      <label for="explorer-q" class="sr-only">Altura, transação ou endereço</label>
      <input
        id="explorer-q"
        name="q"
        value={@query}
        type="text"
        autocomplete="off"
        spellcheck="false"
        placeholder="Altura, id de transação ou endereço brdc1…"
        class="brdc-input min-w-0"
      />
      <button type="submit" class="brdc-btn-primary w-auto px-6">Buscar</button>
    </form>
    """
  end

  defp home(assigns) do
    ~H"""
    <section class="brdc-card-glow p-6" aria-label="Estado da rede">
      <p class="text-sm text-[var(--brdc-muted)]">Rede</p>
      <h1 class="mt-1 text-2xl font-bold" data-decrypt>{@d.status.chain_id}</h1>
      <div class="mt-4 flex flex-wrap gap-2">
        <.chip tone={:green} icon="hero-cube">
          <span data-decrypt>bloco {@d.status.height}</span>
        </.chip>
        <.chip tone={if @d.status.pending > 0, do: :yellow, else: :neutral} icon="hero-clock">
          {@d.status.pending} pendente(s)
        </.chip>
        <.chip tone={:blue} icon="hero-shield-check">{length(@d.validators)} validador(es)</.chip>
        <.chip tone={:yellow} icon="hero-banknotes">
          Em circulação {Explorer.money(@d.status.supply)} BRDC
        </.chip>
      </div>
    </section>

    <div class="grid gap-6 lg:grid-cols-2">
      <section class="brdc-card p-5" aria-label="Esperando bloco">
        <h2 class="text-lg font-bold">Esperando bloco</h2>
        <p :if={@d.pending == []} class="mt-3 text-sm text-[var(--brdc-muted)]">
          Nada pendente. A rede só produz bloco quando há transação.
        </p>
        <ul class="mt-3 space-y-2">
          <li :for={t <- @d.pending}>
            <.tx_row t={t} />
          </li>
        </ul>
      </section>

      <section class="brdc-card p-5" aria-label="Últimos blocos">
        <h2 class="text-lg font-bold">Últimos blocos</h2>
        <p :if={@d.blocks == []} class="mt-3 text-sm text-[var(--brdc-muted)]">
          Ainda não há blocos.
        </p>
        <ul class="mt-3 space-y-2">
          <li :for={b <- @d.blocks}>
            <.link
              patch={~p"/explorer/block/#{b.height}"}
              class="brdc-inset flex items-center justify-between gap-3 p-3"
            >
              <span class="font-bold">#{b.height}</span>
              <span class="truncate font-mono text-xs text-[var(--brdc-muted)]">{Explorer.hex(b.hash)}</span>
              <span class="text-xs text-[var(--brdc-muted)]">{b.tx_count} tx · {b.signers} assin.</span>
            </.link>
          </li>
        </ul>
      </section>
    </div>

    <section class="brdc-card p-5" aria-label="Validadores">
      <h2 class="text-lg font-bold">Validadores</h2>
      <ul class="mt-3 space-y-2">
        <li :for={v <- @d.validators} class="brdc-inset break-all p-3 font-mono text-xs">
          {v.address}
        </li>
      </ul>
      <p class="mt-3 text-xs text-[var(--brdc-muted)]">
        Lista informada pelo nó consultado. Para confiança total, compare com as chaves da gênese da rede.
      </p>
    </section>
    """
  end

  attr :t, :map, required: true

  defp tx_row(assigns) do
    ~H"""
    <.link patch={~p"/explorer/tx/#{@t.id_hex}"} class="brdc-inset block p-3">
      <span class="flex items-center justify-between gap-2">
        <span class="font-semibold">{@t.label}</span>
        <span :if={@t.amount} class="brdc-amount">{Explorer.money(@t.amount)} BRDC</span>
      </span>
      <span class="mt-1 block truncate font-mono text-xs text-[var(--brdc-muted)]">{@t.id_hex}</span>
    </.link>
    """
  end

  defp block_page(assigns) do
    ~H"""
    <section class="brdc-card-glow p-6" aria-label="Bloco">
      <div class="flex items-center justify-between gap-3">
        <h1 class="text-2xl font-bold">Bloco {@d.height}</h1>
        <div class="flex gap-2">
          <.link
            :if={@d.height > 1}
            patch={~p"/explorer/block/#{@d.height - 1}"}
            class="brdc-btn-ghost px-4"
          >Anterior</.link>
          <.link
            :if={@d.height < @d.latest}
            patch={~p"/explorer/block/#{@d.height + 1}"}
            class="brdc-btn-ghost px-4"
          >Próximo</.link>
        </div>
      </div>
      <dl class="mt-4 space-y-3 text-sm">
        <.row label="Hash" value={Explorer.hex(@d.hash, full: true)} mono />
        <.row
          label="Bloco anterior"
          value={if @d.prev_hash, do: Explorer.hex(@d.prev_hash, full: true), else: "(gênese)"}
          mono
        />
        <.row label="Hora" value={Explorer.time(@d.time)} />
        <.row label="Proposto por" value={@d.proposer} mono />
        <.row
          label="Raiz de estado"
          value={if @d.state_root, do: Explorer.hex(@d.state_root, full: true), else: "—"}
          mono
        />
      </dl>
    </section>

    <section class="brdc-card p-5" aria-label="Certificado de commit">
      <div class="flex items-center justify-between gap-3">
        <h2 class="text-lg font-bold">Certificado de commit</h2>
        <.chip :if={@d.verified} tone={:green} icon="hero-check-badge">Conferido</.chip>
        <.chip :if={!@d.verified} tone={:yellow} icon="hero-exclamation-triangle">
          Não conferido
        </.chip>
      </div>
      <p :if={@d.verified} class="mt-3 text-sm text-[var(--brdc-muted)]">
        {length(@d.signers)} validadores assinaram este mesmo bloco (mais de 2/3 do conjunto). A conferência usa as
        chaves que o nó consultado informa: prova que o bloco é consistente, não que o nó é honesto.
      </p>
      <p :if={!@d.verified} class="brdc-alert mt-3">
        {reason_text(@d.reason)} Não confie neste bloco.
      </p>
      <ul :if={@d.signers != []} class="mt-3 space-y-2">
        <li :for={s <- @d.signers} class="brdc-inset break-all p-3 font-mono text-xs">{s}</li>
      </ul>
    </section>

    <section class="brdc-card p-5" aria-label="Transações do bloco">
      <h2 class="text-lg font-bold">Transações ({length(@d.txs)})</h2>
      <ul class="mt-3 space-y-2">
        <li :for={t <- @d.txs}>
          <.tx_row t={t} />
        </li>
      </ul>
    </section>
    """
  end

  defp tx_page(assigns) do
    ~H"""
    <section class="brdc-card-glow p-6" aria-label="Transação">
      <h1 class="text-2xl font-bold">{@d.label}</h1>
      <p :if={@d.amount} class="mt-2">
        <span class="brdc-amount text-4xl">{Explorer.money(@d.amount)}</span> BRDC
      </p>
      <dl class="mt-4 space-y-3 text-sm">
        <.row label="Id" value={@d.id_hex} mono />
        <.row label="De" value={@d.from} mono link={~p"/explorer/account/#{@d.from}"} />
        <.row :if={@d.to} label="Para" value={@d.to} mono link={~p"/explorer/account/#{@d.to}"} />
        <.row label="Taxa" value={"#{Explorer.money(@d.fee)} BRDC"} />
        <.row label="Nonce" value={Integer.to_string(@d.nonce)} />
        <.row
          label="Bloco"
          value={"#{@d.height} (posição #{@d.index})"}
          link={~p"/explorer/block/#{@d.height}"}
        />
        <.row label="Hora" value={Explorer.time(@d.time)} />
      </dl>
    </section>
    """
  end

  defp account_page(assigns) do
    ~H"""
    <section class="brdc-card-glow p-6" aria-label="Conta">
      <p class="text-sm text-[var(--brdc-muted)]">Saldo</p>
      <p class="mt-2"><.amount units={@d.balance} class="text-5xl" unit="BRDC" /></p>
      <p :if={@d.pending_balance != @d.balance} class="mt-2 text-sm text-[var(--brdc-yellow)]">
        Com as pendentes: {Explorer.money(@d.pending_balance)} BRDC
      </p>
      <p class="mt-4 break-all font-mono text-xs">{@d.address}</p>
    </section>

    <section class="brdc-card p-5" aria-label="Histórico">
      <h2 class="text-lg font-bold">Histórico</h2>
      <p :if={@d.history == []} class="mt-3 text-sm text-[var(--brdc-muted)]">
        Nenhuma transação ainda.
      </p>
      <ul class="mt-3 space-y-2">
        <li :for={h <- @d.history}>
          <.link patch={~p"/explorer/tx/#{h.id_hex}"} class="brdc-inset block p-3">
            <span class="flex items-center justify-between gap-2">
              <span class="font-semibold">{h.label}</span>
              <span class="text-xs text-[var(--brdc-muted)]">
                {if h.role == :sender, do: "enviou", else: "recebeu"} · bloco {h.height}
              </span>
            </span>
            <span class="mt-1 block truncate font-mono text-xs text-[var(--brdc-muted)]">{h.id_hex}</span>
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  defp reason_text(:no_certificate),
    do:
      "Este nó não guarda certificado para este bloco (rede de um nó só, sem consenso, ou bloco antigo)."

  defp reason_text(:different_block), do: "O certificado é de outro bloco."
  defp reason_text(:wrong_height), do: "O certificado é de outra altura."
  defp reason_text(other), do: "O certificado não fecha (#{inspect(other)})."

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :mono, :boolean, default: false
  attr :link, :string, default: nil

  defp row(assigns) do
    ~H"""
    <div>
      <dt class="text-xs text-[var(--brdc-muted)]">{@label}</dt>
      <dd class={["break-all", @mono && "font-mono text-xs"]}>
        <.link :if={@link} patch={@link} class="underline decoration-[var(--brdc-green)]">{@value}</.link>
        <span :if={!@link}>{@value}</span>
      </dd>
    </div>
    """
  end
end
