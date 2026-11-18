defmodule Mix.Tasks.Brdc.Devnet.Status do
  @shortdoc "Mostra o estado de cada validador da rede de teste"
  @moduledoc """
  Para cada validador: se o processo está vivo, a altura, as transações pendentes e o último bloco. No fim diz
  se há **quórum** (mais de 2/3 no ar) e se os validadores estão **de acordo** (mesma altura e mesmo bloco).

      mix brdc.devnet.status [--dir net]
  """
  use Mix.Task
  alias BrdcDev.Net
  alias BrdcNode.Client

  @impl Mix.Task
  def run(args) do
    Net.help?(args, @moduledoc) && exit(:normal)
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])
    Mix.Task.run("app.config")
    dir = Net.dir(opts)

    cfg =
      Net.read_config(dir) ||
        Mix.raise("nenhuma rede criada em #{dir}; rode `mix brdc.devnet.init`")

    rows = for i <- 1..cfg.validators, do: row(dir, cfg, i)
    Enum.each(rows, &print/1)
    summary(cfg, rows)
  end

  defp row(dir, cfg, i) do
    pid = Net.read_pid(dir, i)
    alive = Net.alive?(pid)
    status = if alive, do: Client.status(Net.endpoint(cfg, i)), else: {:error, :down}
    %{i: i, pid: pid, alive: alive, port: Net.public_port(cfg, i), status: status}
  end

  defp print(%{status: {:ok, s}} = r) do
    Mix.shell().info(
      "  v#{r.i}  no ar   pid #{r.pid}  :#{r.port}  altura #{s.height}  pendentes #{s.pending}  bloco #{short(s.last_hash)}"
    )
  end

  defp print(%{alive: true} = r),
    do: Mix.shell().info("  v#{r.i}  vivo mas não responde  pid #{r.pid}  :#{r.port}")

  defp print(r), do: Mix.shell().info("  v#{r.i}  parado")

  defp summary(cfg, rows) do
    up = Enum.filter(rows, &match?(%{status: {:ok, _}}, &1))
    need = div(2 * cfg.validators, 3) + 1
    quorum = if length(up) >= need, do: "COM quórum", else: "SEM quórum (a rede espera)"
    Mix.shell().info("\n#{length(up)} de #{cfg.validators} no ar (precisa de #{need}): #{quorum}")

    heads = up |> Enum.map(fn %{status: {:ok, s}} -> {s.height, s.last_hash} end) |> Enum.uniq()

    case heads do
      [] ->
        :ok

      [_] ->
        Mix.shell().info("os validadores no ar estão de acordo")

      _ ->
        Mix.shell().info(
          "atenção: alturas ou blocos diferentes entre os validadores (pode ser só atraso; rode de novo)"
        )
    end
  end

  defp short(nil), do: "-"
  defp short(hash), do: hash |> binary_part(0, 4) |> Base.encode16(case: :lower)
end
