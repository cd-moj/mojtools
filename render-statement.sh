#!/bin/bash
# render-statement.sh <enunciado-file> [fmt=md] [examples-html-file] [title] -> HTML completo no stdout.
#
# FONTE ÚNICA de renderização do enunciado: o MESMO que o "Pré-visualizar" do editor
# (handlers/problems/preview.sh) usa. Pandoc standalone — NÃO depende do Makefile nem do
# scaffolding (.pandocfilters/pandoc.css) de cada repositório, então funciona igual para
# problemas legados e para os criados no Gitea. "O que você pré-visualiza é o que o aluno vê."
#
# O TÍTULO vem do CAMPO (não do "% Título" do markdown): injeta um <h1> no topo do body e remove
# um bloco "% ..." legado do início do fonte. Injeta os exemplos (HTML pronto, num arquivo) antes
# de </body> e um CSS limpo. Usado por preview.sh, gen-problem-json.sh e validate-problem.sh.
set -u
src="${1:?uso: render-statement.sh <enunciado> [fmt] [examples-html-file] [title]}"
fmt="${2:-md}"; exf="${3:-}"; title="${4:-}"
case "$fmt" in org) pf=org;; tex) pf=latex;; *) pf=markdown;; esac

esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# o título vem do campo -> remove um "% Título" legado da 1ª linha do fonte (não duplica)
rsrc="$src"
if head -1 "$src" 2>/dev/null | grep -q '^%'; then rsrc="$(mktemp)"; tail -n +2 "$src" > "$rsrc"; fi

html="$(pandoc -f "$pf" --mathml -s --embed-resources "$rsrc" 2>/dev/null)"
[[ -n "$html" ]] || html="$(printf '<!DOCTYPE html><html><head></head><body><pre>%s</pre></body></html>' \
  "$(esc < "$rsrc")")"
[[ "$rsrc" != "$src" ]] && rm -f "$rsrc"

th=""; [[ -n "$title" ]] && th="<h1 class=\"moj-title\">$(printf '%s' "$title" | esc)</h1>"

style='<style>body{font-family:system-ui,Arial,sans-serif;max-width:52rem;margin:1rem auto;padding:0 1rem;line-height:1.55;color:#111}.moj-title{margin:.2rem 0 1.1rem}pre{background:#f3f4f6;padding:.6rem;border-radius:6px;overflow:auto;white-space:pre-wrap}.moj-exemplos h2{margin-top:1.2rem}.moj-exemplo{border:1px solid #e5e7eb;border-radius:8px;padding:.2rem .8rem;margin:.6rem 0}.moj-exemplo h3,.moj-exemplo h4{margin:.5rem 0 .2rem}.moj-exemplo-nota{margin:.1rem 0 .5rem;color:#374151}img{max-width:100%}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.2rem .5rem}</style>'

awk -v exfile="$exf" -v st="$style" -v th="$th" '
  BEGIN{ s=""; if(exfile!=""){ while((getline l<exfile)>0) s=s l "\n" } }
  /<\/head>/{ print st }
  /<body[^>]*>/{ print; if(th!="") print th; next }
  /<\/body>/{ printf "%s", s }
  { print }' <<<"$html"
