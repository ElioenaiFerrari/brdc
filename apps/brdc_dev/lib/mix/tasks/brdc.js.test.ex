defmodule Mix.Tasks.Brdc.Js.Test do
  @shortdoc "Testa a criptografia do navegador (Node) contra os vetores do Elixir"
  @moduledoc """
  Roda os testes de `apps/brdc_web/assets/js/crypto/*.test.mjs` com o Node (mesmo `crypto.subtle` do
  navegador) e confere os vetores de criptografia (`tools/js/verify-vectors.mjs`).

      mix brdc.js.test
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    node =
      System.find_executable("node") || Mix.raise("precisa do Node (24 ou mais novo) no PATH")

    root = File.cwd!()
    tests = Path.wildcard(Path.join(root, "apps/brdc_web/assets/js/crypto/*.test.mjs"))
    if tests == [], do: Mix.raise("nenhum teste JS encontrado em apps/brdc_web/assets/js/crypto")

    run!(node, ["--test" | tests])
    vectors = Path.join(root, "tools/js/verify-vectors.mjs")
    if File.exists?(vectors), do: run!(node, [vectors])
  end

  defp run!(node, args) do
    case System.cmd(node, args, into: IO.stream(:stdio, :line), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, code} -> Mix.raise("node #{hd(args)} falhou (código #{code})")
    end
  end
end
