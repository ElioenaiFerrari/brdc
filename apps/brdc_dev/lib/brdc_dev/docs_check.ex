defmodule BrdcDev.DocsCheck do
  @moduledoc """
  Confere a documentação viva (regra do `CLAUDE.md`), sem shell: links e imagens relativos, texto alternativo,
  diagramas só em PNG, todo app no README, molde dos fluxos e a linha de status dos ADRs.

  `check/1` devolve a lista de problemas (vazia = tudo certo), então é testável com uma pasta de mentira.
  """

  @flow_sections [
    "## Resumo",
    "## Passo a passo",
    "## Onde está no código",
    "## Limites honestos"
  ]

  @spec check(Path.t()) :: [String.t()]
  def check(root) do
    mds = markdown_files(root)

    broken_links(root, mds) ++
      missing_alt(root, mds) ++
      generated_diagrams(root) ++
      apps_missing_in_readme(root) ++
      flows(root) ++
      adrs(root)
  end

  defp markdown_files(root) do
    [Path.join(root, "README.md") | Path.wildcard(Path.join(root, "docs/**/*.md"))]
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  defp rel(root, path), do: Path.relative_to(path, root)

  # 1) links e imagens relativos precisam existir
  defp broken_links(root, mds) do
    for file <- mds,
        [_, target] <- Regex.scan(~r/\]\(([^)]*)\)/, File.read!(file)),
        path = link_path(target),
        path != nil,
        not File.exists?(Path.join(Path.dirname(file), path)) do
      "link quebrado: #{rel(root, file)} -> #{target}"
    end
  end

  defp link_path(target) do
    cond do
      target == "" ->
        nil

      String.starts_with?(target, ["http", "mailto:", "#"]) ->
        nil

      true ->
        target |> String.split("#", parts: 2) |> hd() |> then(&if(&1 == "", do: nil, else: &1))
    end
  end

  # 2) imagens sem texto alternativo
  defp missing_alt(root, mds) do
    for file <- mds,
        {line, n} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        String.contains?(line, "![]") do
      "imagem sem texto alternativo: #{rel(root, file)}:#{n}"
    end
  end

  # 3) só PNG: SVG e HTML de diagramas não são guardados
  defp generated_diagrams(root) do
    for ext <- ~w(svg html),
        path <- Path.wildcard(Path.join(root, "docs/diagrams/*.#{ext}")) do
      "diagrama gerado não deve ser versionado: #{rel(root, path)} (guarde só o .png)"
    end
  end

  # 4) todo app da umbrella aparece no README
  defp apps_missing_in_readme(root) do
    readme = root |> Path.join("README.md") |> File.read() |> elem_or("")

    for mix <- Path.wildcard(Path.join(root, "apps/*/mix.exs")),
        name = mix |> Path.dirname() |> Path.basename(),
        not String.contains?(readme, name) do
      "app '#{name}' não aparece no README.md"
    end
  end

  # 5) fluxos: molde obrigatório
  defp flows(root) do
    for file <- Path.wildcard(Path.join(root, "docs/flows/[0-9]*.md")),
        text = File.read!(file),
        section <- @flow_sections,
        not Regex.match?(~r/^#{Regex.escape(section)}/m, text) do
      "#{rel(root, file)} sem a seção '#{section}'"
    end
  end

  # 6) ADRs: a linha de status
  defp adrs(root) do
    for file <- Path.wildcard(Path.join(root, "docs/adr/[0-9]*.md")),
        not Regex.match?(~r/^\*\*Status:\*\*/m, File.read!(file)) do
      "#{rel(root, file)} sem a linha '**Status:**'"
    end
  end

  defp elem_or({:ok, v}, _), do: v
  defp elem_or(_, default), do: default
end
