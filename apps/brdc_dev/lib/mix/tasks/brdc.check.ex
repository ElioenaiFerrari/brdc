defmodule Mix.Tasks.Brdc.Check do
  @shortdoc "Portão de qualidade: formato, credo, compilação sem avisos, testes, JS e docs"
  @moduledoc """
  O portão de qualidade (o mesmo do CI). Roda, em ordem, e mostra o resultado de cada passo:

    1. `mix format --check-formatted`
    2. `mix credo --strict`
    3. `mix compile --force --warnings-as-errors`
    4. `mix test`
    5. os testes JS da criptografia do navegador (`mix brdc.js.test`; pulado se não há `node`)
    6. `mix brdc.docs.check`

      mix brdc.check [--skip-js] [--skip-docs]

  Os passos do Elixir rodam em `MIX_ENV=test`. Termina com erro se algum passo falhar.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [skip_js: :boolean, skip_docs: :boolean])

    steps =
      [
        {"formato", {:mix, ["format", "--check-formatted"]}},
        {"credo", {:mix, ["credo", "--strict"]}},
        {"compilação sem avisos", {:mix, ["compile", "--force", "--warnings-as-errors"]}},
        {"testes", {:mix, ["test"]}}
      ] ++
        if(opts[:skip_js] || System.find_executable("node") == nil,
          do: [],
          else: [{"testes JS", {:task, "brdc.js.test"}}]
        ) ++
        if(opts[:skip_docs], do: [], else: [{"docs", {:task, "brdc.docs.check"}}])

    failed = for {name, step} <- steps, not run_step(name, step), do: name

    if failed == [] do
      Mix.shell().info("\nbrdc.check: tudo certo (#{length(steps)} passos)")
    else
      Mix.raise("brdc.check: falhou em: #{Enum.join(failed, ", ")}")
    end
  end

  defp run_step(name, step) do
    Mix.shell().info("\n==> #{name}")

    case step do
      {:mix, args} ->
        {_, code} =
          System.cmd("mix", args,
            env: [{"MIX_ENV", "test"}],
            into: IO.stream(:stdio, :line),
            stderr_to_stdout: true
          )

        report(name, code == 0)

      {:task, task} ->
        report(name, try_task(task))
    end
  end

  defp try_task(task) do
    Mix.Task.rerun(task)
    true
  rescue
    e in Mix.Error ->
      Mix.shell().error(Exception.message(e))
      false
  end

  defp report(name, ok?) do
    Mix.shell().info(if(ok?, do: "    ok: #{name}", else: "    FALHOU: #{name}"))
    ok?
  end
end
