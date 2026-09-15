#!/bin/bash
# render-statement.sh <enunciado-file> [fmt=md] [examples-html-file] [title] [lang=pt] -> HTML completo no stdout.
#
# FONTE ÚNICA de renderização do enunciado: o MESMO que o "Pré-visualizar" do editor
# (handlers/problems/preview.sh) usa. Pandoc standalone — NÃO depende do Makefile nem do
# scaffolding (.pandocfilters/pandoc.css) de cada repositório, então funciona igual para
# problemas legados e para os criados no Gitea. "O que você pré-visualiza é o que o aluno vê."
#
# O TÍTULO vem do CAMPO (não do "% Título" do markdown): injeta um <h1> no topo do body e remove
# um bloco "% ..." legado do início do fonte. Injeta os exemplos (HTML pronto, num arquivo) antes
# de </body> e um CSS limpo. Usado por preview.sh, gen-problem-json.sh e validate-problem.sh.
# O 5º argumento é o IDIOMA do enunciado (pt|en|es, ver statement-langs.sh): só ajusta o
# `<html lang="…">` — a tradução mora em docs/enunciado.<lang>.md e os rótulos dos exemplos vêm
# prontos no HTML dos exemplos. Um renderizador só, para todos os idiomas.
set -u
# dir deste script — p/ achar o lua-filter dos grafos (graphviz.lua, ver docs/enunciado-grafos.md)
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SELF="."
src="${1:?uso: render-statement.sh <enunciado> [fmt] [examples-html-file] [title] [lang]}"
fmt="${2:-md}"; exf="${3:-}"; title="${4:-}"; lang="${5:-pt}"
case "$lang" in en) hlang=en;; es) hlang=es;; *) hlang=pt-BR;; esac
case "$fmt" in org) pf=org;; tex) pf=latex;; *) pf=markdown;; esac

esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# --resource-path do pandoc resolve imagens relativas ao CWD do CHAMADOR, não à
# pasta do enunciado (achado real: gen-problem-json.sh/preview.sh chamam com o
# enunciado por caminho absoluto mas sem "cd" pra dentro de docs/ antes -- sem
# isso, toda imagem local vira <img src="arquivo.png"> quebrado em vez de
# embutida em base64, mesmo com --embed-resources). Captura o dir do FONTE
# original (antes da possível cópia p/ tempfile abaixo, que iria pra /tmp).
srcdir="$(cd "$(dirname "$src")" 2>/dev/null && pwd)" || srcdir="."

# o título vem do campo -> remove um "% Título" legado da 1ª linha do fonte (não duplica)
rsrc="$src"
if head -1 "$src" 2>/dev/null | grep -q '^%'; then rsrc="$(mktemp)"; tail -n +2 "$src" > "$rsrc"; fi

html="$(pandoc -f "$pf" --mathml -s --embed-resources --resource-path="$srcdir" --lua-filter="$SELF/graphviz.lua" "$rsrc" 2>/dev/null)"
[[ -n "$html" ]] || html="$(printf '<!DOCTYPE html><html><head></head><body><pre>%s</pre></body></html>' \
  "$(esc < "$rsrc")")"
[[ "$rsrc" != "$src" ]] && rm -f "$rsrc"

th=""; [[ -n "$title" ]] && th="<h1 class=\"moj-title\">$(printf '%s' "$title" | esc)</h1>"

style='<style>body{font-family:system-ui,Arial,sans-serif;max-width:52rem;margin:1rem auto;padding:0 1rem;line-height:1.55;color:#111}.moj-title{margin:.2rem 0 1.1rem}pre{background:#f3f4f6;padding:.6rem;border-radius:6px;overflow:auto;white-space:pre-wrap}.moj-exemplos h2{margin-top:1.2rem}.moj-exemplo{border:1px solid #e5e7eb;border-radius:8px;padding:.2rem .8rem;margin:.6rem 0}.moj-exemplo h3,.moj-exemplo h4{margin:.5rem 0 .2rem}.moj-exemplo-nota{margin:.1rem 0 .5rem;color:#374151}img{max-width:100%}.moj-graph{margin:1rem 0}.moj-graph.center{text-align:center}.moj-graph svg{max-width:100%;height:auto}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:.2rem .5rem}</style>'

# <html lang>: o pandoc emite `<html xmlns=… lang="" xml:lang="">` (ou sem lang) — a 1ª tag <html
# ganha o idioma do enunciado (leitor de tela, hifenização, CSS :lang()).
awk -v exfile="$exf" -v st="$style" -v th="$th" -v hl="$hlang" '
  BEGIN{ s=""; if(exfile!=""){ while((getline l<exfile)>0) s=s l "\n" } }
  !done && /<html/{ gsub(/ (xml:)?lang(="[^"]*")?/,""); sub(/<html/,"<html lang=\"" hl "\""); done=1 }
  /<\/head>/{ print st }
  /<body[^>]*>/{ print; if(th!="") print th; next }
  /<\/body>/{ printf "%s", s }
  { print }' <<<"$html"
