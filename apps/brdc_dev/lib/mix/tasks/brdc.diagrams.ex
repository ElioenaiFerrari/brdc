defmodule Mix.Tasks.Brdc.Diagrams do
  @shortdoc "Regenera docs/diagrams/*.png a partir de scripts/diagrams"
  @moduledoc """
  Regenera os diagramas (só PNG) pelo gerador em `scripts/diagrams/` (skill `diagram-design`, tema do projeto).
  Precisa do Python 3 e do Brave.

      mix brdc.diagrams
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    python = System.find_executable("python3") || Mix.raise("precisa do python3 no PATH")

    case System.cmd(python, ["scripts/diagrams/generate.py"],
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("o gerador de diagramas falhou (código #{code})")
    end
  end
end
