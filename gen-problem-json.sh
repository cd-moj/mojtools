#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify it under the
#terms of the GNU General Public License as published by the Free Software
#Foundation, either version 3 of the License, or (at your option) any later
#version. See <http://www.gnu.org/licenses/>.

# gen-problem-json.sh — gera o índice servível do treino a partir de um pacote de
# problema: contests/treino/var/jsons/<id>.json = {id,title,time_limits,tags,collections,
# statement_html_b64,author,statement_langs,statements}. Fecha o passo que faltava (o synctreino
# só fazia git pull + make).
#
# IDIOMAS (2026-09-15, ver statement-langs.sh): PT segue em `title`/`statement_html_b64` (compat
# total); cada tradução docs/enunciado.<lang>.md vira `statements.<lang> = {title, html_b64}`
# (título de `.moj-meta.json` `titles[lang]`, senão o PT) e `statement_langs` lista os idiomas
# servidos, PT primeiro. Notas de exemplo por idioma (docs/notes/<sample>.<lang>.md) com fallback PT.
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
source "$MOJTOOLS_DIR/statement-langs.sh"

# ----- 1. detecta o enunciado + formato (o HTML é renderizado no passo 6) -----
ENUNF="$(stmt_file "$PKG" pt)" || ENUNF=""
[[ -n "$ENUNF" && "$ENUNF" == "$PKG/docs/"* ]] || { echo "gen-problem-json: sem docs/enunciado.{md,org,tex} p/ $ID" >&2; exit 2; }
FMT="$(stmt_fmt "$ENUNF")"

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
# TLOVERRIDE do conf do PACOTE: o autor decide o TL na marra e o treino exibe o EFETIVO
# (override[lang] // override[default] // calibrado[lang]). O conf é CÓDIGO do autor e este
# script roda no SERVIDOR: parse por sed, NUNCA source. Espelho de tl_conf_overrides/
# tl_override_apply (cdmoj lib/tl-store.sh) — duplicação pequena e consciente: repos independentes.
ov_json="$(sed -nE 's/^[[:space:]]*TLOVERRIDE\[([A-Za-z0-9]{1,16})\]=([0-9]+\.?[0-9]*|\.[0-9]+)[[:space:]]*(#.*)?$/\1\t\2/p' \
    "$PKG/conf" 2>/dev/null \
  | jq -Rnc '[inputs | split("\t") | select(length==2)
              | {((.[0] | if .=="py3" or .=="py2" then "py" else . end)): .[1]}] | add // {}')"
if [[ -n "$ov_json" && "$ov_json" != '{}' ]]; then
  tl_json="$(jq -cn --argjson tl "$tl_json" --argjson ov "$ov_json" '
    (($tl|keys) + ($ov|keys) | unique) as $ks
    | reduce $ks[] as $k ({}; .[$k] = ($ov[$k] // $ov["default"] // $tl[$k]))
    | with_entries(select(.value != null) | .value |= tostring)')"
  [[ -n "$tl_json" ]] || tl_json='{}'
fi

# ----- 5+6. exemplos (por idioma) + render (MESMO renderizador do "Pré-visualizar") + base64 -----
# Os exemplos vêm dos testes (sempre aparentes, batendo com os testes reais); o HTML deles é o do
# `stmt_samples_html` (statement-langs.sh) — o mesmo do preview do editor. Um render por idioma.
# b64 do HTML em ARQUIVO (entra no jq por --rawfile): statement grande estourava o ARG_MAX no
# --arg -> jq falhava -> json VAZIO -> o problema sumia do treino (jq -s pula arquivo vazio).
LANGS="$(stmt_langs_of "$PKG")"
declare -A B64F=() LTITLE=()
n=0
for lang in $LANGS; do
  lf="$(stmt_file "$PKG" "$lang")"; lfmt="$(stmt_fmt "$lf")"
  ltitle="$title"
  if [[ "$lang" != pt ]]; then
    lt="$(jq -r --arg l "$lang" '.titles[$l] // ""' "$meta" 2>/dev/null)"; [[ -n "$lt" ]] && ltitle="$lt"
  fi
  exf="$(mktemp)"; stmt_samples_html "$PKG" "$lang" > "$exf"; (( n == 0 )) && n="${STMT_SAMPLES_N:-0}"
  tmp_html="$(mktemp)"
  bash "$MOJTOOLS_DIR/render-statement.sh" "$lf" "$lfmt" "$exf" "$ltitle" "$lang" > "$tmp_html" 2>/dev/null
  if [[ ! -s "$tmp_html" ]]; then
    rm -f "$exf" "$tmp_html"
    [[ "$lang" == pt ]] && { echo "gen-problem-json: render do enunciado FALHOU p/ $ID" >&2; exit 2; }
    echo "gen-problem-json: render do enunciado $lang FALHOU p/ $ID (idioma pulado)" >&2; continue
  fi
  b64f="$(mktemp)"; base64 -w0 < "$tmp_html" | tr -d '\n' > "$b64f"; rm -f "$exf" "$tmp_html"
  B64F[$lang]="$b64f"; LTITLE[$lang]="$ltitle"
done
[[ -n "${B64F[pt]:-}" ]] || { echo "gen-problem-json: sem enunciado PT renderizado p/ $ID" >&2; exit 2; }
# samples como DADO ([{name,input,output}]): a MESMA seleção do HTML (stmt_sample_names) — nunca
# tests/input inteiro; é o que /treino/problem e /contest/samples servem (2026-09-16). Em arquivo
# (--slurpfile), como o resto: nada de dado de pacote em argv do jq.
samples_f="$(mktemp)"; stmt_samples_json "$PKG" > "$samples_f"
b64f="${B64F[pt]}"
# statements (só os idiomas não-PT) montado em ARQUIVO, um --rawfile por idioma (nunca argv)
stmts_f="$(mktemp)"; printf '{}' > "$stmts_f"; langs_json='["pt"]'
for lang in $LANGS; do
  [[ "$lang" == pt || -z "${B64F[$lang]:-}" ]] && continue
  jq -c --arg l "$lang" --arg t "${LTITLE[$lang]}" --rawfile h "${B64F[$lang]}" '. + {($l): {title:$t, html_b64:$h}}' "$stmts_f" > "$stmts_f.n" && mv -f "$stmts_f.n" "$stmts_f"
  langs_json="$(jq -c --arg l "$lang" '. + [$l]' <<<"$langs_json")"
  rm -f "${B64F[$lang]}"
done

# ----- 7. público? FAIL-CLOSED: só é público se o .moj-meta.json disser public:true -----
# ESTE É O PORTÃO DA LISTA PÚBLICA DO TREINO (var/jsons/ é servido SEM login: lista + enunciado).
# NUNCA teste booleano com o `//` do jq: ele trata FALSE como vazio, então `.public // "unset"`
# devolvia "unset" p/ public:false — indistinguível de "ausente". A checagem virava código morto, o
# default (que era `true`) prevalecia e TODO problema privado ia parar no índice público, com o
# enunciado servido a qualquer anônimo. Prova em elaboração vazava. Use `jq -e '.public == true'`.
public=false                                                       # default: PRIVADO
[[ -f "$meta" ]] && jq -e '.public == true' "$meta" >/dev/null 2>&1 && public=true
grep -q '^PUBLIC=no' "$PKG/conf" 2>/dev/null && public=false       # legado: força privado
# 2ª camada (vem do servidor): org sem `public_allowed` NUNCA gera índice público, doa o que doer
# o meta (import legado, org rebaixada, bug futuro). Ver cdmoj lib/tl-store.sh index_problem_bg.
[[ "${MOJ_FORCE_PRIVATE:-0}" == 1 ]] && public=false

# ----- 8. escreve (ou remove) o índice servível -----
mkdir -p "$TREINO_JSONS" "$(dirname "$TREINO_JSONS")/jsons-private" 2>/dev/null
# `public` VAI no json: quem SERVE (handlers/treino/{problems,problem}.sh, anônimos) recusa
# `.public == false` — assim um json privado que reapareça em var/jsons/ por qualquer caminho
# ainda não é servido (defesa em profundidade; json legado sem o campo continua passando).
out_json="$(jq -cn --arg id "$ID" --arg title "$title" --arg author "$author" --argjson tl "$tl_json" \
  --argjson tags "$tags" --argjson colls "$colls" --argjson langs "$langs" --rawfile html "$b64f" \
  --argjson pub "$public" --argjson slangs "$langs_json" --slurpfile stmts "$stmts_f" --slurpfile smp "$samples_f" \
  '{id:$id, title:$title, author:$author, time_limits:$tl, tags:$tags, collections:$colls, languages:$langs, public:$pub,
    statement_langs:$slangs, statement_html_b64:$html, samples:($smp[0] // [])}
   + (if ($stmts[0]|length) > 0 then {statements:$stmts[0]} else {} end)')"
rm -f "$b64f" "$stmts_f" "$samples_f"
priv="$(dirname "$TREINO_JSONS")/jsons-private/$ID.json"
tmpj="$(dirname "$priv")/.$ID.tmp"                                 # tmp no dir PRIVADO: um mv falho
printf '%s' "$out_json" > "$tmpj" && mv -f "$tmpj" "$priv"         # não deixa lixo no dir PÚBLICO
# O cache da lista (var/problems.json) tem de morrer nos DOIS ramos: ele alimenta /treino/problems
# (TTL 5min) e o banco de contests `cc_bank_json` — que o lê **sem TTL nenhum**. Sem isto, um
# problema despublicado (ex.: por um tl-report) continuaria no banco de sorteio para sempre.
CACHE="$(dirname "$TREINO_JSONS")/problems.json"
if [[ "$public" == true ]]; then
  ptmp="$TREINO_JSONS/.$ID.pub.tmp"
  # HARDLINK (2026-09-16), não cópia: eram 2 GB duplicados. Seguro porque TODO escritor dos dois
  # caminhos grava tmp+mv (nunca em lugar) — o link se desfaz sozinho na próxima escrita.
  { ln -f "$priv" "$ptmp" 2>/dev/null || cp -f "$priv" "$ptmp"; } && mv -f "$ptmp" "$TREINO_JSONS/$ID.json"  # publicação ATÔMICA (rename)
  rm -f "$CACHE"
  echo "gen-problem-json: $ID publicado (title='$title', exemplos=$n, idiomas=${langs_json})"
else
  rm -f "$TREINO_JSONS/$ID.json" "$CACHE"
  echo "gen-problem-json: $ID privado (fora do treino; cópia em jsons-private)"
fi
