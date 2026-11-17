#!/usr/bin/env bash
# Confere a documentação viva (regra em CLAUDE.md): links, imagens, apps no README, texto alternativo e idioma.
set -u
cd "$(dirname "$0")/.."
erros=0
falha() { echo "docs-check: $1"; erros=$((erros + 1)); }

mds=$(find README.md docs -name '*.md' | sort)

# 1) links e imagens relativos precisam existir
for f in $mds; do
  dir=$(dirname "$f")
  grep -o '\](\([^)]*\))' "$f" | sed 's/^](//; s/)$//' | while read -r alvo; do
    case "$alvo" in http*|mailto:*|\#*|"") continue ;; esac
    caminho="${alvo%%#*}"
    [ -z "$caminho" ] && continue
    [ -e "$dir/$caminho" ] || echo "ALVO $f -> $alvo"
  done
done > /tmp/brdc-docs-check.$$ 2>&1
while read -r l; do falha "link quebrado: ${l#ALVO }"; done < <(grep '^ALVO' /tmp/brdc-docs-check.$$)
rm -f /tmp/brdc-docs-check.$$

# 2) imagens sem texto alternativo
for f in $mds; do
  grep -n '!\[\]' "$f" | while read -r l; do echo "ALT $f:$l"; done
done > /tmp/brdc-docs-check-alt.$$
while read -r l; do falha "imagem sem texto alternativo: ${l#ALT }"; done < <(cat /tmp/brdc-docs-check-alt.$$)
rm -f /tmp/brdc-docs-check-alt.$$

# 3) só PNG: SVG/HTML de diagramas não são guardados
for p in docs/diagrams/*.svg docs/diagrams/*.html; do
  [ -e "$p" ] && falha "diagrama gerado não deve ser versionado: $p (guarde só o .png)"
done

# 4) todo app da umbrella aparece no README
for t in apps/*/mix.exs; do
  nome=$(basename "$(dirname "$t")")
  grep -q "$nome" README.md || falha "app '$nome' não aparece no README.md"
done

# 5) fluxos: molde obrigatório
for f in docs/flows/[0-9]*.md; do
  [ -e "$f" ] || continue
  for sec in "## Resumo" "## Passo a passo" "## Onde está no código" "## Limites honestos"; do
    grep -q "^$sec" "$f" || falha "$f sem a seção '$sec'"
  done
done

# 6) ADRs: número no nome e o campo de status
for f in docs/adr/[0-9]*.md; do
  grep -q "^\*\*Status:\*\*" "$f" || falha "$f sem a linha '**Status:**'"
done

if [ "$erros" -gt 0 ]; then echo "docs-check: $erros problema(s)"; exit 1; fi
echo "docs-check: ok"
