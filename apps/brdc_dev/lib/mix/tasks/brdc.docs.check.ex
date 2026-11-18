defmodule Mix.Tasks.Brdc.Docs.Check do
  @shortdoc "Confere links, imagens, apps no README, molde dos fluxos e status dos ADRs"
  @moduledoc """
  Confere a documentação viva (regra do `CLAUDE.md`). Sai com erro se houver problema.

      mix brdc.docs.check [--root PASTA]
  """
  use Mix.Task
  alias BrdcDev.DocsCheck

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [root: :string])
    root = opts[:root] || File.cwd!()

    case DocsCheck.check(root) do
      [] ->
        Mix.shell().info("docs-check: ok")

      problems ->
        Enum.each(problems, &Mix.shell().error("docs-check: #{&1}"))
        Mix.raise("docs-check: #{length(problems)} problema(s)")
    end
  end
end
