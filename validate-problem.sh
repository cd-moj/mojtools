#!/bin/bash
#This file is part of CD-MOJ. GPLv3+. See <http://www.gnu.org/licenses/>.

# validate-problem.sh — PORTÃO de qualidade de um pacote de problema. Gera um
# relatório em $RUNDIR/validation/<id>.json e, se passar, gera o índice do treino
# (chama gen-problem-json.sh). "Só sobe/publica o que funciona."
#
#   uso:  validate-problem.sh <pkgdir> [<id>]
#   retorna 0 se passou (e indexou), !=0 se reprovou.
#
# Checagens (hard, salvo indicado):
#   has_author        — existe ./author (o Makefile exige p/ descobrir o problema)
#   has_statement     — existe docs/enunciado.{md,org,tex}
#   html_builds       — make <problema>.html sai 0 (stderr do pandoc vai p/ detail)
#   examples_present  — >=1 par tests/input|output (exemplos sempre aparentes)
#   tests_paired      — todo input tem output e vice-versa
#   has_good_sol      — >=1 solução em sols/good/
#   good_sol_accepts  — (se VALIDATE_RUN_SOLS=1 e há bwrap) cada sols/good é Accepted
set -u

PKG="${1:?uso: validate-problem.sh <pkgdir> [id]}"
PKG="$(cd "$PKG" 2>/dev/null && pwd)" || { echo "validate: pkg '$1' inexistente" >&2; exit 1; }
REPODIR="$(dirname "$PKG")"; PROB="$(basename "$PKG")"; REPO="$(basename "$REPODIR")"
ID="${2:-$REPO#$PROB}"
SELF="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

: "${RUNDIR:=/home/ribas/moj/run}"
: "${VALDIR:=$RUNDIR/validation}"
: "${VALIDATE_RUN_SOLS:=1}"            # 0 = pula a execução das good (útil em dev sem sandbox)
HOSTNAME="${HOSTNAME:-$(hostname)}"
mkdir -p "$VALDIR" 2>/dev/null

declare -a CK
add(){ # add <name> <ok 0|1> [detail]
  CK+=("$(jq -cn --arg n "$1" --argjson ok "$([[ "$2" == 1 ]] && echo true || echo false)" \
        --arg d "${3:-}" '{name:$n, ok:$ok, detail:$d}')"); }

# --- has_author ---
[[ -f "$PKG/author" ]] && add has_author 1 || add has_author 0 "falta o arquivo 'author'"

# --- has_statement ---
stmt=""; for e in md org tex; do [[ -f "$PKG/docs/enunciado.$e" ]] && stmt="$e" && break; done
[[ -n "$stmt" ]] && add has_statement 1 "enunciado.$stmt" || add has_statement 0 "sem docs/enunciado.{md,org,tex}"

# --- html_builds ---
html_built=false
err="$( cd "$REPODIR" && make -B "$PROB.html" 2>&1 >/dev/null )" && [[ -s "$REPODIR/$PROB.html" ]] \
  && { html_built=true; add html_builds 1; } \
  || add html_builds 0 "$(printf '%s' "$err" | tail -3 | tr '\n' ' ')"

# vaza LaTeX de PROSA no HTML? (informativo — sinaliza p/ curadoria; math via mathml é OK)
render_leak=""
[[ "$html_built" == true ]] && render_leak="$(grep -oE '\\(textbf|textit|subsection|section|arquivoProblema|begin\{(itemize|enumerate|center)\}|emph|underline)' "$REPODIR/$PROB.html" 2>/dev/null | sort -u | tr '\n' ' ')"

# --- examples / tests pairing ---
ninput=0; npair=0; unpaired=""
if [[ -d "$PKG/tests/input" ]]; then
  for f in "$PKG/tests/input/"*; do
    [[ -e "$f" ]] || continue; ((ninput++)); b="$(basename "$f")"
    if [[ -f "$PKG/tests/output/$b" ]]; then ((npair++)); else unpaired+="$b "; fi
  done
fi
# outputs sem input
if [[ -d "$PKG/tests/output" ]]; then
  for f in "$PKG/tests/output/"*; do [[ -e "$f" ]] || continue; b="$(basename "$f")"
    [[ -f "$PKG/tests/input/$b" ]] || unpaired+="out:$b "; done
fi
(( npair >= 1 )) && add examples_present 1 "$npair par(es)" || add examples_present 0 "sem pares input/output"
[[ -z "$unpaired" ]] && add tests_paired 1 "$npair par(es)" || add tests_paired 0 "sem par: $unpaired"

# --- has_good_sol ---
ngood=0; [[ -d "$PKG/sols/good" ]] && ngood="$(find "$PKG/sols/good" -maxdepth 1 -type f 2>/dev/null | wc -l)"
(( ngood >= 1 )) && add has_good_sol 1 "$ngood" || add has_good_sol 0 "sols/good vazio"

# --- good_sol_accepts (opcional; roda no juiz) ---
gsa_ran=false
if [[ "$VALIDATE_RUN_SOLS" != 0 ]] && command -v bwrap >/dev/null 2>&1 && (( ngood >= 1 )); then
  gsa_ran=true; bad=""
  for sol in "$PKG/sols/good/"*; do
    [[ -f "$sol" ]] || continue
    lang="${sol##*.}"
    verdict="$(bash "$SELF/build-and-test.sh" "$lang" "$sol" "$PKG" y 2>/dev/null | tail -n1)"
    [[ "$verdict" =~ ^Accepted ]] || bad+="$(basename "$sol"):${verdict:-?} "
  done
  [[ -z "$bad" ]] && add good_sol_accepts 1 "todas Accepted" || add good_sol_accepts 0 "$bad"
fi

# --- tl_present (soft: informativo) ---
tl_present=false; { [[ -f "$PKG/tl" ]] || [[ -f "$PKG/tl.$HOSTNAME" ]]; } && tl_present=true

# --- veredicto do portão: todas as hard precisam passar ---
report="$(printf '%s\n' "${CK[@]}" | jq -s -c \
  --arg id "$ID" --argjson now "$EPOCHSECONDS" \
  --argjson hb "$html_built" --argjson tp "$tl_present" --arg rw "$render_leak" '
  { id:$id, at:$now, checks:., html_built:$hb, tl_present:$tp,
    render_warnings:($rw|gsub("^ +| +$";"")), ok: (map(.ok) | all) }')"
tmp="$VALDIR/.$ID.tmp"; printf '%s' "$report" > "$tmp" && mv -f "$tmp" "$VALDIR/$ID.json"
ok="$(jq -r '.ok' <<<"$report")"

if [[ "$ok" == true ]]; then
  RUNDIR="$RUNDIR" bash "$SELF/gen-problem-json.sh" "$PKG" "$ID" >/dev/null 2>&1 \
    && echo "validate: $ID OK -> indexado" || echo "validate: $ID OK mas indexação falhou" >&2
  exit 0
else
  echo "validate: $ID REPROVADO -> $(jq -rc '[.checks[]|select(.ok==false)|.name] | join(",")' <<<"$report")" >&2
  exit 1
fi
