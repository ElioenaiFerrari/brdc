defmodule BrdcWebWeb.BrdcComponents do
  @moduledoc """
  Componentes da identidade visual da BRDC (docs/design/README.md): valor com decimais apagados,
  chips de estado, navegação inferior e teclado numérico. Só HTML e classes; sem JavaScript e sem
  estilo em linha (CSP estrita).
  """
  use Phoenix.Component
  import BrdcWebWeb.CoreComponents, only: [icon: 1]
  alias BrdcWebWeb.Format

  @doc """
  Valor em BRDC com os centavos apagados, como na referência (`12.480,`**57**`).

  ## Exemplo
      <.amount units={12_480_570_000} class="text-5xl" />
  """
  attr :units, :integer, required: true, doc: "valor em unidades mínimas (1 BRDC = 1.000.000)"
  attr :class, :string, default: "text-4xl"
  attr :unit, :string, default: nil, doc: "sufixo, ex.: BRDC"

  def amount(assigns) do
    {whole, cents} = Format.split(assigns.units)
    assigns = assign(assigns, whole: whole, cents: cents)

    ~H"""
    <span class={["brdc-amount", @class]}>
      {@whole}<span class="brdc-dim">,{@cents}</span>
      <span :if={@unit} class="brdc-dim ml-1 text-[0.45em] font-semibold">{@unit}</span>
    </span>
    """
  end

  @doc "Chip de estado. Cor **e** texto (a cor nunca é a única informação)."
  attr :tone, :atom, default: :neutral, values: [:neutral, :green, :blue, :yellow]
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <span class={[
      "brdc-chip",
      @tone == :green && "brdc-chip-green",
      @tone == :blue && "brdc-chip-blue",
      @tone == :yellow && "brdc-chip-yellow"
    ]}>
      <.icon :if={@icon} name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc "Navegação inferior (até 5 itens). `current` marca a seção atual."
  attr :current, :atom, required: true
  attr :items, :list, default: nil

  def bottom_nav(assigns) do
    assigns = assign_new(assigns, :nav, fn -> assigns.items || default_items() end)

    ~H"""
    <nav
      aria-label="Principal"
      class="fixed inset-x-0 bottom-0 z-20 mx-auto flex max-w-md lg:hidden items-center justify-around border-t border-white/10 bg-[#080c0a]/95 px-2 pb-[max(0.5rem,env(safe-area-inset-bottom))] pt-2 backdrop-blur"
    >
      <a
        :for={{key, label, ico} <- @nav}
        href="#"
        class="brdc-nav-item"
        aria-current={key == @current && "page"}
      >
        <.icon name={ico} class="size-6" />
        <span>{label}</span>
        <span class="brdc-nav-dot"></span>
      </a>
    </nav>
    """
  end

  defp default_items do
    [
      {:home, "Início", "hero-home"},
      {:assets, "Bens", "hero-building-library"},
      {:contracts, "Contratos", "hero-document-text"},
      {:credentials, "Credenciais", "hero-identification"},
      {:activity, "Atividade", "hero-clock"}
    ]
  end

  @doc "Teclado numérico (visual; a ligação com o valor vem na tela de envio)."
  def keypad(assigns) do
    ~H"""
    <div class="grid grid-cols-3 gap-y-1 px-2" role="group" aria-label="Teclado numérico">
      <button :for={k <- ~w(1 2 3 4 5 6 7 8 9)} type="button" class="brdc-key" aria-label={k}>
        {k}
      </button>
      <button type="button" class="brdc-key" aria-label="vírgula">,</button>
      <button type="button" class="brdc-key" aria-label="0">0</button>
      <button type="button" class="brdc-key" aria-label="apagar">
        <.icon name="hero-backspace" class="size-7" />
      </button>
    </div>
    """
  end
end
