#!/bin/bash
# kattis/normalize.sh — cria uma VIEW efêmera no layout MOJ de um pacote Kattis-NATIVO, p/ o
# juiz (build-and-test.sh/calibreitor.sh) rodar SEM importar. Symlinks p/ os testes/soluções
# (não copia dados grandes). Use p/ a Fase 3 (MOJ guardar pacotes Kattis-nativos).
#   uso: normalize.sh <kattis-pkgdir> <viewdir>
set -u
KT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; source "$KT_DIR/lib.sh"
SRC="${1:?uso: normalize.sh <kattis-pkgdir> <viewdir>}"; V="${2:?viewdir}"
[[ -f "$SRC/problem.yaml" ]] || { echo "sem problem.yaml em $SRC" >&2; exit 1; }
have_py || { echo "preciso de python3+pyyaml" >&2; exit 1; }
y="$(kt_parse_yaml "$SRC/problem.yaml")"
A="$(cd "$SRC" && pwd)"   # caminho absoluto p/ os symlinks
mkdir -p "$V/docs" "$V/tests/input" "$V/tests/output" "$V/sols/good"

# conf + tl (derivados; pequenos -> escritos)
cf="$(jq -r '.limits.time_multipliers.ac_to_time_limit // empty' <<<"$y")"; [[ -n "$cf" ]] || cf=1.35
mem="$(jq -r '.limits.memory // empty' <<<"$y")"; outm="$(jq -r '.limits.output // empty' <<<"$y")"
{ printf 'TLMOD[calibrafactor]=%s\n' "$cf"
  [[ "$mem" =~ ^[0-9]+$ ]] && printf 'ULIMITS[-v]=%s\n' "$((mem*1024))"
  [[ "$outm" =~ ^[0-9]+$ ]] && printf 'ULIMITS[-f]=%s\n' "$((outm*1024))"
  printf 'ALLOWPARALLELTEST=y\n'; } > "$V/conf"
tl="$(jq -r '.limits.time_limit // empty' <<<"$y")"
side='{}'; [[ -f "$A/.kattis.json" ]] && side="$(cat "$A/.kattis.json")"
{ echo '#kattis view'
  if [[ "$(jq -r '(.per_language_tl // {})|length' <<<"$side")" -gt 0 ]]; then jq -r '.per_language_tl|to_entries[]|"TL[\(.key)]=\(.value)"' <<<"$side"
  elif [[ -n "$tl" ]]; then printf 'TL[default]=%s\n' "$tl"; fi; } > "$V/tl"

# enunciado (symlink, opcional) + testes (symlink, sample->sampleN, secret achatado)
st="$(find "$A/statement" -maxdepth 1 \( -name 'problem.*.md' -o -name 'problem.*.tex' \) 2>/dev/null | head -1)"
[[ -n "$st" ]] && ln -sf "$st" "$V/docs/enunciado.${st##*.}"
shopt -s nullglob   # script standalone: globs ligados, sem noglob
i=0
for f in "$A/data/sample"/*.in; do i=$((i+1)); b="$(basename "$f" .in)"; ln -sf "$f" "$V/tests/input/sample$i"; [[ -f "$A/data/sample/$b.ans" ]] && ln -sf "$A/data/sample/$b.ans" "$V/tests/output/sample$i"; done
[[ -d "$A/data/secret" ]] && while IFS= read -r f; do rel="${f#"$A"/data/secret/}"; n="$(printf '%s' "${rel%.in}" | tr '/' '_' | tr -cd 'A-Za-z0-9._-')"
  ln -sf "$f" "$V/tests/input/$n"; [[ -f "${f%.in}.ans" ]] && ln -sf "${f%.in}.ans" "$V/tests/output/$n"; done < <(find "$A/data/secret" -name '*.in' 2>/dev/null | sort)

# soluções (symlink) + checker bridge
declare -A SMAP=( [accepted]=good [wrong_answer]=wrong [time_limit_exceeded]=slow [run_time_error]=wrong [brute_force]=pass )
for v in accepted wrong_answer time_limit_exceeded run_time_error brute_force; do d="$A/submissions/$v"; [[ -d "$d" ]] || continue
  mkdir -p "$V/sols/${SMAP[$v]}"; for s in "$d"/*; do [[ -f "$s" && "$s" != *.yaml ]] && ln -sf "$s" "$V/sols/${SMAP[$v]}/$(basename "$s")"; done; done
if [[ -d "$A/output_validator" ]]; then mkdir -p "$V/scripts"; ln -sf "$A/output_validator" "$V/output_validator"; cp "$KT_DIR/validator-bridge.sh" "$V/scripts/compare.sh"; chmod +x "$V/scripts/compare.sh"; fi
[[ -f "$A/author" ]] && ln -sf "$A/author" "$V/author" || echo "Kattis" > "$V/author"
echo "normalize: $SRC -> $V (view com symlinks)"
