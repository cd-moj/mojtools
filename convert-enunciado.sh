#!/bin/bash
#This file is part of CD-MOJ. GPLv3+. See <http://www.gnu.org/licenses/>.

# convert-enunciado.sh — converte o enunciado de um problema p/ Markdown CANÔNICO
# (estilo saad/Codeforces: `% Título`, descrição, `## Entrada`, `## Saída`, opcional
# `## Restrições`). Os EXEMPLOS vêm dos testes (gen-problem-json injeta), então não
# dependemos de exemplos embutidos. Best-effort; sinaliza o que precisa de curadoria.
#
#   uso:  convert-enunciado.sh <pkgdir> [--write]
#         (sem --write: imprime o md no stdout; --write grava docs/enunciado.md + .bak)
set -u
PKG="${1:?uso: convert-enunciado.sh <pkgdir> [--write]}"; PKG="$(cd "$PKG" 2>/dev/null && pwd)" || exit 1
WRITE=0; [[ "${2:-}" == "--write" ]] && WRITE=1
DOC="$PKG/docs"
src=""; fmt=""
for e in tex org md; do [[ -f "$DOC/enunciado.$e" ]] && { src="$DOC/enunciado.$e"; fmt="$e"; break; }; done
[[ -n "$src" ]] || { echo "convert: sem docs/enunciado.{tex,org,md} em $PKG" >&2; exit 1; }

tmp="$(mktemp)" out="$(mktemp)"
case "$fmt" in
  md)  cat "$src" > "$tmp" ;;
  org) pandoc -f org -t gfm "$src" 2>/dev/null > "$tmp" ;;
  tex) # neutraliza macros próprias antes do pandoc (\arquivoProblema some; \section* -> \section)
       sed -E -e 's/\\arquivoProblema\{[^}]*\}//g' -e 's/\\section\*\{/\\section{/g' "$src" \
         | pandoc -f latex -t gfm 2>/dev/null > "$tmp" ;;
esac

# normaliza cabeçalhos de seção -> canônico
sed -i -E \
  -e 's/^#+[[:space:]]*(Entrada|Input)[[:space:]]*$/## Entrada/I' \
  -e 's/^#+[[:space:]]*(Sa[íi]da|Output)[[:space:]]*$/## Saída/I' \
  -e 's/^#+[[:space:]]*(Restri[çc][õo]es|Constraints)[[:space:]]*$/## Restrições/I' \
  -e 's/^#+[[:space:]]*(Exemplos?|Examples?|Sample.*)[[:space:]]*$/## Exemplos/I' \
  "$tmp"

# título = 1º heading; corpo = resto sem esse heading
title="$(grep -m1 -E '^#+[[:space:]]' "$tmp" | sed -E 's/^#+[[:space:]]*//; s/[[:space:]]*$//')"
[[ -z "$title" ]] && { title="$(grep -m1 '^%' "$src" 2>/dev/null | sed 's/^%[[:space:]]*//')"; }
[[ -z "$title" ]] && title="$(basename "$PKG")"
printf '%% %s\n\n' "$title" > "$out"
awk 'done==0 && /^#+[[:space:]]/ {done=1; next} {print}' "$tmp" >> "$out"

# limpa LaTeX de prosa residual no markdown
sed -i -E \
  -e 's/\\includegraphics(\[[^]]*\])?\{([^}]*)\}/![](\2)/g' \
  -e 's/\\textbf\{([^}]*)\}/**\1**/g' \
  -e 's/\\textit\{([^}]*)\}/*\1*/g' \
  -e 's/\\emph\{([^}]*)\}/*\1*/g' \
  -e 's/\\texttt\{([^}]*)\}/`\1`/g' \
  -e "s/\\\\tt[[:space:]]+([A-Za-z0-9]+)/\`\1\`/g" \
  "$out"

# o que sobrou de LaTeX de prosa? -> curadoria manual
leak="$(grep -oE '\\(arquivoProblema|subsection|section|textbf|textit|begin\{(itemize|enumerate|center|tabular)\})' "$out" 2>/dev/null | sort -u | tr '\n' ' ')"

if (( WRITE )); then
  cp -f "$src" "$src.bak" 2>/dev/null
  cp -f "$out" "$DOC/enunciado.md"
  echo "convert: $(basename "$PKG") -> docs/enunciado.md (de .$fmt)${leak:+   ⚠ CURAR: $leak}"
else
  cat "$out"
  [[ -n "$leak" ]] && echo "## ⚠ CONVERT-CURAR: $leak" >&2
fi
rm -f "$tmp" "$out"
