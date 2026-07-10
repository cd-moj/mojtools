#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify it under the
#terms of the GNU General Public License as published by the Free Software
#Foundation, either version 3 of the License, or (at your option) any later
#version. See <http://www.gnu.org/licenses/>.

# gen-problem-json.sh — gera o índice servível do treino a partir de um pacote de
# problema: contests/treino/var/jsons/<id>.json = {id,title,time_limits,tags,collections,
# statement_html_b64,author}. Fecha o passo que faltava (o synctreino só fazia git pull + make).
#
#   uso:  gen-problem-json.sh <pkgdir> [<id>]
#         <pkgdir> = .../<repo>/<problema>   (o pai é o repo, com o Makefile)
#         <id>     = default <repo>#<problema>
#
# Renderiza o enunciado pelo MESMO renderizador do "Pré-visualizar" (render-statement.sh,
# pandoc standalone — sem Makefile/scaffolding do repo). INJETA os exemplos a partir dos testes
# (tests/input|output), sempre aparentes e batendo com os testes reais. Respeita .moj-meta.json.
set -u

PKG="${1:?uso: gen-problem-json.sh <pkgdir> [id]}"
PKG="$(cd "$PKG" 2>/dev/null && pwd)" || { echo "gen-problem-json: pkg '$1' inexistente" >&2; exit 1; }
REPODIR="$(dirname "$PKG")"
PROB="$(basename "$PKG")"
REPO="$(basename "$REPODIR")"
ID="${2:-$REPO#$PROB}"

: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${TREINO_JSONS:=$CONTESTSDIR/treino/var/jsons}"
: "${SAMPLE_LIMIT:=2}"                 # nº máximo de exemplos a injetar
: "${MOJTOOLS_DIR:=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)}"
: "${MOJ_TL_STORE:=${RUNDIR:-/home/ribas/moj/run}/tl}"   # TLs reportados pelos juízes
HOSTNAME="${HOSTNAME:-$(hostname)}"

esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# ----- 1. detecta o enunciado + formato (o HTML é renderizado no passo 6) -----
ENUNF=""; FMT=md
for e in md org tex; do [[ -f "$PKG/docs/enunciado.$e" ]] && { ENUNF="$PKG/docs/enunciado.$e"; FMT="$e"; break; }; done
[[ -n "$ENUNF" ]] || { echo "gen-problem-json: sem docs/enunciado.{md,org,tex} p/ $ID" >&2; exit 2; }

# ----- 2. título -----
title=""
if [[ -f "$PKG/docs/enunciado.md" ]]; then
  title="$(grep -m1 '^%' "$PKG/docs/enunciado.md" 2>/dev/null | sed 's/^%[[:space:]]*//')"
elif [[ -f "$PKG/docs/enunciado.org" ]]; then
  title="$(grep -m1 -i '^#+title:' "$PKG/docs/enunciado.org" 2>/dev/null | sed 's/^#+[Tt][Ii][Tt][Ll][Ee]:[[:space:]]*//')"
elif [[ -f "$PKG/docs/enunciado.tex" ]]; then
  title="$(grep -m1 -E '\\(section|title)\{' "$PKG/docs/enunciado.tex" 2>/dev/null | sed -E 's/.*\\(section|title)\{([^}]*)\}.*/\2/')"
fi
# override por .moj-meta.json; fallback p/ o nome do problema
meta="$PKG/.moj-meta.json"
dt=""; [[ -f "$meta" ]] && dt="$(jq -r '.display_title // empty' "$meta" 2>/dev/null)"
[[ -n "$dt" ]] && title="$dt"
[[ -n "$title" ]] || title="$PROB"

# ----- 2b. coleções (do .moj-meta.json; um problema pode estar em várias) -----
# Verbatim do meta (como o editor via read_problem_source); sem inventar default de nome-de-repo.
colls='[]'
[[ -f "$meta" ]] && colls="$(jq -c '(.collections // [])' "$meta" 2>/dev/null)"; [[ -n "$colls" ]] || colls='[]'

# ----- 2c. linguagens de submissão (restrição por-problema; []/ausente = todas) -----
# Servido no json do treino p/ o dropdown filtrar (web/treino/problema) e p/ ser o último elo
# da cadeia de fallback de contest (handlers/contest/problems.sh).
langs='[]'
[[ -f "$meta" ]] && langs="$(jq -c '(.languages // [])' "$meta" 2>/dev/null)"; [[ -n "$langs" ]] || langs='[]'

# ----- 3. tags (linhas começando com #, minúsculas) -----
tags='[]'
[[ -f "$PKG/tags" ]] && tags="$(grep -E '^#' "$PKG/tags" 2>/dev/null | tr 'A-Z' 'a-z' \
  | jq -R . | jq -s -c '.' 2>/dev/null)"; [[ -n "$tags" ]] || tags='[]'

# ----- 3b. autor (atribuição; pode ter vários, 1 por linha; texto livre — exibido verbatim) -----
# NÃO dividir por vírgula: ela já aparece DENTRO da linha ("adaptado por…", "Nome, versão…").
author=""
[[ -f "$PKG/author" ]] && author="$(grep -vE '^[[:space:]]*$' "$PKG/author" | paste -sd', ' -)"

# ----- 4. time_limits -----
# Modelo cache: os juízes calibram no cache local e REPORTAM o TL (store por host); o TL
# servível = MÁX entre hosts p/ o checksum ATUAL do pacote. Se o pacote mudou e ninguém
# recalibrou ainda, fica {} (o tl antigo é descartado). Fallback legado: tl.<host>/tl no
# pacote (fallback p/ pacotes antigos sem o campo).
tl_json='{}'
storef="$MOJ_TL_STORE/$ID.json"
cur_cks="$(bash "$MOJTOOLS_DIR/tl-checksum.sh" "$PKG" 2>/dev/null)"
# chaves py3/py2 são LEGADAS (calibração pré-unificação do python): fundem em 'py' por MAX.
if [[ -f "$storef" && -n "$cur_cks" ]]; then
  tl_json="$(jq -c --arg cks "$cur_cks" '
    if (.checksum // "")!=$cks or ((.hosts // {})|length)==0 then {}
    else [ .hosts[].tl // {} ]
         | reduce (.[]|to_entries[]) as $e ({};
             ($e.key | if .=="py3" or .=="py2" then "py" else . end) as $k
             | .[$k]=([(.[$k]//0),($e.value|tonumber? // 0)]|max))
         | with_entries(.value |= tostring) end
  ' "$storef" 2>/dev/null)"; [[ -n "$tl_json" ]] || tl_json='{}'
fi
if [[ "$tl_json" == '{}' ]]; then
  TLFILE="$PKG/tl"; [[ -f "$PKG/tl.$HOSTNAME" ]] && TLFILE="$PKG/tl.$HOSTNAME"
  if [[ -f "$TLFILE" ]]; then
    declare -A TL; declare -A TLMOD
    source "$TLFILE" 2>/dev/null
    { for k in "${!TL[@]}"; do printf '%s\t%s\n' "$k" "${TL[$k]}"; done; } \
      | jq -R -s -c 'split("\n")|map(select(length>0)|split("\t")
          |{((.[0]) | if .=="py3" or .=="py2" then "py" else . end):.[1]})|add // {}' \
      > /tmp/.tljson.$$ 2>/dev/null && tl_json="$(cat /tmp/.tljson.$$)"; rm -f /tmp/.tljson.$$
    unset TL TLMOD
  fi
fi

# ----- 5. exemplos a partir dos testes (sempre aparentes, batendo com os testes) -----
samples_html=""
declare -a SAMPLES
if [[ -f "$PKG/samples" ]]; then
  mapfile -t SAMPLES < <(grep -vE '^[[:space:]]*$' "$PKG/samples")
elif compgen -G "$PKG/tests/input/sample*" >/dev/null 2>&1; then
  mapfile -t SAMPLES < <(cd "$PKG/tests/input" && ls -1v sample* 2>/dev/null)   # exemplos = sample* (todos)
else
  mapfile -t SAMPLES < <(ls -1 "$PKG/tests/input" 2>/dev/null | head -n "$SAMPLE_LIMIT")
fi
# explicação por exemplo (na ordem dos exemplos): docs/sample-notes.json = ["nota1", "nota2", ...]
# Lidas por ÍNDICE com jq (não 'mapfile', que quebraria notas multi-linha em várias entradas).
NOTESF="$PKG/docs/sample-notes.json"
n=0; i=0
for s in "${SAMPLES[@]}"; do
  in="$PKG/tests/input/$s"; out="$PKG/tests/output/$s"
  if [[ -f "$in" && -f "$out" ]]; then
    samples_html+="<div class=\"moj-exemplo\"><h3>Entrada</h3><pre>$(esc < "$in")</pre>"
    samples_html+="<h3>Saída</h3><pre>$(esc < "$out")</pre>"
    note=""; [[ -f "$NOTESF" ]] && note="$(jq -r --argjson k "$i" '.[$k] // ""' "$NOTESF" 2>/dev/null)"
    if [[ -n "$note" ]]; then
      nh="$(printf '%s' "$note" | pandoc -f markdown -t html 2>/dev/null)"; [[ -n "$nh" ]] || nh="<p>$(printf '%s' "$note" | esc)</p>"
      samples_html+="<div class=\"moj-exemplo-nota\">$nh</div>"
    fi
    samples_html+="</div>"; (( n++ ))
  fi
  (( i++ ))
done
if [[ -n "$samples_html" ]]; then
  samples_html="<section class=\"moj-exemplos\"><h2>Exemplos</h2>$samples_html</section>"
fi

# ----- 6. renderiza (MESMO renderizador do "Pré-visualizar") + injeta exemplos + base64 -----
exf="$(mktemp)"; [[ -n "$samples_html" ]] && printf '%s' "$samples_html" > "$exf"
tmp_html="$(mktemp)"
bash "$MOJTOOLS_DIR/render-statement.sh" "$ENUNF" "$FMT" "$exf" "$title" > "$tmp_html" 2>/dev/null
[[ -s "$tmp_html" ]] || { echo "gen-problem-json: render do enunciado FALHOU p/ $ID" >&2; rm -f "$exf" "$tmp_html"; exit 2; }
# b64 do HTML em ARQUIVO (entra no jq por --rawfile): statement grande estourava o ARG_MAX no
# --arg -> jq falhava -> json VAZIO -> o problema sumia do treino (jq -s pula arquivo vazio).
b64f="$(mktemp)"; base64 -w0 < "$tmp_html" | tr -d '\n' > "$b64f"; rm -f "$exf" "$tmp_html"

# ----- 7. público? (default: não tem PUBLIC=no no conf, e .moj-meta.public != false) -----
public=true
grep -q '^PUBLIC=no' "$PKG/conf" 2>/dev/null && public=false
[[ -f "$meta" ]] && [[ "$(jq -r '.public // "unset"' "$meta" 2>/dev/null)" == "false" ]] && public=false

# ----- 8. escreve (ou remove) o índice servível -----
mkdir -p "$TREINO_JSONS" "$(dirname "$TREINO_JSONS")/jsons-private" 2>/dev/null
out_json="$(jq -cn --arg id "$ID" --arg title "$title" --arg author "$author" --argjson tl "$tl_json" \
  --argjson tags "$tags" --argjson colls "$colls" --argjson langs "$langs" --rawfile html "$b64f" \
  '{id:$id, title:$title, author:$author, time_limits:$tl, tags:$tags, collections:$colls, languages:$langs, statement_html_b64:$html}')"
rm -f "$b64f"
priv="$(dirname "$TREINO_JSONS")/jsons-private/$ID.json"
tmpj="$TREINO_JSONS/.$ID.tmp"
printf '%s' "$out_json" > "$tmpj" && mv -f "$tmpj" "$priv"          # cópia sempre (p/ contests privados)
if [[ "$public" == true ]]; then
  cp -f "$priv" "$TREINO_JSONS/$ID.json"
  echo "gen-problem-json: $ID publicado (title='$title', exemplos=$n)"
else
  rm -f "$TREINO_JSONS/$ID.json"
  echo "gen-problem-json: $ID privado (fora do treino; cópia em jsons-private)"
fi
