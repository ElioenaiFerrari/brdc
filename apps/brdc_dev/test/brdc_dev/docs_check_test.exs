defmodule BrdcDev.DocsCheckTest do
  use ExUnit.Case, async: true
  alias BrdcDev.DocsCheck

  @moduletag :tmp_dir

  defp write(root, path, text) do
    full = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, text)
  end

  defp good_flow,
    do: "# F\n## Resumo\n## Passo a passo\n## Onde está no código\n## Limites honestos\n"

  defp base(root) do
    write(root, "README.md", "apps: brdc_x\n")
    write(root, "apps/brdc_x/mix.exs", "")
    write(root, "docs/flows/01-a.md", good_flow())
    write(root, "docs/adr/0001-a.md", "# A\n\n**Status:** Aceito\n")
  end

  test "uma documentação em ordem não tem problemas", %{tmp_dir: root} do
    base(root)
    assert DocsCheck.check(root) == []
  end

  test "link quebrado, imagem sem alt e diagrama gerado são apontados", %{tmp_dir: root} do
    base(root)

    write(
      root,
      "docs/guia.md",
      "veja [x](nao-existe.md) e [web](https://x.com) e [ancora](#a) e ![](img.png)\n"
    )

    write(root, "docs/diagrams/a.svg", "<svg/>")
    problems = DocsCheck.check(root)
    assert Enum.any?(problems, &(&1 =~ "link quebrado: docs/guia.md -> nao-existe.md"))
    assert Enum.any?(problems, &(&1 =~ "imagem sem texto alternativo: docs/guia.md:1"))
    assert Enum.any?(problems, &(&1 =~ "diagrama gerado não deve ser versionado"))
    refute Enum.any?(problems, &(&1 =~ "x.com" or &1 =~ "#a"))
  end

  test "link com âncora aponta para o arquivo; arquivo existente passa", %{tmp_dir: root} do
    base(root)
    write(root, "docs/b.md", "# B\n")
    write(root, "docs/guia.md", "[b](b.md#secao) [pai](../README.md)\n")
    assert DocsCheck.check(root) == []
  end

  test "app fora do README, fluxo sem seção e ADR sem status são apontados", %{tmp_dir: root} do
    base(root)
    write(root, "apps/brdc_y/mix.exs", "")
    write(root, "docs/flows/02-b.md", "# F\n## Resumo\n")
    write(root, "docs/adr/0002-b.md", "# B\n")
    problems = DocsCheck.check(root)
    assert "app 'brdc_y' não aparece no README.md" in problems
    assert "docs/flows/02-b.md sem a seção '## Passo a passo'" in problems
    assert "docs/flows/02-b.md sem a seção '## Limites honestos'" in problems
    assert "docs/adr/0002-b.md sem a linha '**Status:**'" in problems
  end

  test "este repositório passa na própria conferência" do
    root = Path.expand("../../../..", __DIR__)
    assert DocsCheck.check(root) == []
  end
end
