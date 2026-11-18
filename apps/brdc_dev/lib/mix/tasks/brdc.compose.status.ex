defmodule Mix.Tasks.Brdc.Compose.Status do
  @shortdoc "Mostra cada validador do laboratório: altura, pares, rodada, evidências e pendentes"
  @moduledoc """
  Consulta cada validador pela porta que o Docker publica e mostra o que ele vê: altura, quantos pares estão
  conectados agora, o motor de consenso (parado, ou altura/rodada/passo), evidências de equivocação e transações
  pendentes. Quórum e acordo no fim.

      mix brdc.compose.status [--dir compose]
  """
  use Mix.Task
  alias BrdcDev.{Compose, Net}

  @impl Mix.Task
  def run(args) do
    if Net.help?(args, @moduledoc), do: exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])
    Mix.Task.run("app.config")
    dir = opts[:dir] || Compose.default_dir()

    print(
      Compose.read_config(dir) ||
        Mix.raise("laboratório não criado: rode `mix brdc.compose.init`")
    )
  end

  @doc false
  def print(cfg) do
    rows = Compose.status(cfg)
    Mix.shell().info("nó  porta  altura  pares  motor                 evid  pend  último bloco")

    for {i, r} <- rows, do: Mix.shell().info(line(cfg, i, r))

    up = for {_, {:ok, x}} <- rows, do: x
    need = div(2 * cfg.validators, 3) + 1
    heights = up |> Enum.map(& &1.status.last_hash) |> Enum.uniq()

    Mix.shell().info(
      "\n#{length(up)} de #{cfg.validators} no ar (precisa de #{need}): " <>
        if(length(up) >= need, do: "COM quórum", else: "SEM quórum")
    )

    cond do
      up == [] ->
        :ok

      length(heights) == 1 ->
        Mix.shell().info("os validadores no ar estão de acordo")

      true ->
        Mix.shell().info(
          "ATENÇÃO: os validadores no ar divergem no último bloco (podem estar sincronizando)"
        )
    end
  end

  defp line(cfg, i, {:ok, %{status: st, consensus: c}}) do
    engine =
      case c.engine do
        nil -> "parado"
        e -> "h#{e.height} r#{e.round} #{e.step}"
      end

    last =
      if st.last_hash,
        do: String.slice(Base.encode16(st.last_hash, case: :lower), 0, 8),
        else: "—"

    cells = [
      {"v#{i}", 4},
      {Compose.client_port(cfg, i), 7},
      {st.height, 8},
      {length(c.connected), 7},
      {engine, 22},
      {c.evidence, 6},
      {c.pending, 6}
    ]

    Enum.map_join(cells, fn {v, w} -> v |> to_string() |> String.pad_trailing(w) end) <> last
  end

  defp line(cfg, i, {:error, reason}),
    do: "v#{i}   #{Compose.client_port(cfg, i)}   FORA DO AR (#{inspect(reason)})"
end
