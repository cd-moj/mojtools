#!/bin/bash
# kattis/import.sh — pacote ICPC/Kattis -> pacote MOJ (julgável). Não mexe no juiz.
#   uso: import.sh <pacote (dir | .tar[.gz/.bz2/.zst] | .zip | .kpp)> <out-pkgdir>
set -u
KT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; source "$KT_DIR/lib.sh"
SRC="${1:?uso: import.sh <pacote> <out-pkgdir>}"; OUT="${2:?out-pkgdir}"
have_py || { echo "preciso de python3 + pyyaml" >&2; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
NOTES=()

# 1) materializa a raiz do pacote (extrai se arquivo)
if [[ -d "$SRC" ]]; then root="$SRC"
else
  mkdir -p "$WORK/x"
  if [[ "$(head -c2 "$SRC" 2>/dev/null)" == "PK" ]]; then unzip -qq -o "$SRC" -d "$WORK/x" 2>/dev/null || { echo "zip inválido" >&2; exit 1; }
  else tar -xf "$SRC" -C "$WORK/x" --no-same-owner 2>/dev/null || { echo "arquivo inválido" >&2; exit 1; }; fi
  root="$WORK/x"
fi
py="$(find "$root" -maxdepth 3 -name problem.yaml 2>/dev/null | head -1)"
[[ -n "$py" ]] || { echo "sem problem.yaml no pacote" >&2; exit 1; }
root="$(dirname "$py")"
y="$(kt_parse_yaml "$root/problem.yaml")" || { echo "problem.yaml ilegível" >&2; exit 1; }
side='{}'; [[ -f "$root/.kattis.json" ]] && side="$(cat "$root/.kattis.json" 2>/dev/null)"; [[ -n "$side" ]] || side='{}'

mkdir -p "$OUT/docs" "$OUT/tests/input" "$OUT/tests/output" "$OUT/sols/good"

# 2) conf (ac_to_time_limit->calibrafactor ; memory/output->ULIMITS)
cf="$(jq -r '.limits.time_multipliers.ac_to_time_limit // empty' <<<"$y")"; [[ -n "$cf" ]] || cf=1.35
mem="$(jq -r '.limits.memory // empty' <<<"$y")"; outm="$(jq -r '.limits.output // empty' <<<"$y")"
{ printf 'TLMOD[calibrafactor]=%s\n' "$cf"
  [[ "$mem"  =~ ^[0-9]+$ ]] && printf 'ULIMITS[-v]=%s\n' "$((mem*1024))"
  [[ "$outm" =~ ^[0-9]+$ ]] && printf 'ULIMITS[-f]=%s\n' "$((outm*1024))"
  printf 'ALLOWPARALLELTEST=y\n'; } > "$OUT/conf"

# 3) tl (single time_limit->default; restaura por-linguagem do sidecar se houver)
tl="$(jq -r '.limits.time_limit // empty' <<<"$y")"
{ echo '#importado do Kattis'
  if [[ "$(jq -r '(.per_language_tl // {}) | length' <<<"$side")" -gt 0 ]]; then
    jq -r '.per_language_tl | to_entries[] | "TL[\(.key)]=\(.value)"' <<<"$side"
  elif [[ -n "$tl" ]]; then printf 'TL[default]=%s\n' "$tl"; fi; } > "$OUT/tl"

# 4) author / tags
jq -r '(.credits.authors // .credits // []) | if type=="array" then map(if type=="object" then (.name//"") else . end)|join(" e ") elif type=="string" then . else "" end' <<<"$y" > "$OUT/author"
[[ -s "$OUT/author" ]] || echo "Importado (ICPC)" > "$OUT/author"
jq -r '(.keywords // [])[]? | "#\(.)"' <<<"$y" > "$OUT/tags"

# 5) statement: escolhe a língua (MOJ_STATEMENT_LANG -> en -> pt-BR -> 1ª)
st=""; for cand in "$MOJ_STATEMENT_LANG" en pt-BR pt; do for ext in md tex; do [[ -f "$root/statement/problem.$cand.$ext" ]] && { st="$root/statement/problem.$cand.$ext"; break 2; }; done; done
[[ -n "$st" ]] || st="$(find "$root/statement" -maxdepth 1 \( -name 'problem.*.md' -o -name 'problem.*.tex' \) 2>/dev/null | head -1)"
if [[ -n "$st" ]]; then cp "$st" "$OUT/docs/enunciado.${st##*.}"
  set +o noglob; shopt -s nullglob; for img in "$root/statement"/*.{png,jpg,jpeg,svg}; do cp "$img" "$OUT/docs/"; done; shopt -u nullglob; set -o noglob
else
  pdf="$(find "$root/statement" -maxdepth 1 -name 'problem.*.pdf' 2>/dev/null | head -1)"
  [[ -n "$pdf" ]] && { cp "$pdf" "$OUT/docs/"; NOTES+=("enunciado só em PDF (não-editável)"); } || NOTES+=("sem enunciado md/tex")
fi

# 6) tests: sample->sampleN ; secret (recursivo, achata grupos)->nome
i=0; set +o noglob; shopt -s nullglob
for f in "$root/data/sample"/*.in; do i=$((i+1)); b="$(basename "$f" .in)"; cp "$f" "$OUT/tests/input/sample$i"; [[ -f "$root/data/sample/$b.ans" ]] && cp "$root/data/sample/$b.ans" "$OUT/tests/output/sample$i"; done
shopt -u nullglob; set -o noglob
ngroups=0; [[ -d "$root/data/secret" ]] && while IFS= read -r f; do
  rel="${f#"$root"/data/secret/}"; name="$(printf '%s' "${rel%.in}" | tr '/' '_' | tr -cd 'A-Za-z0-9._-')"
  [[ "$rel" == */* ]] && ngroups=1
  cp "$f" "$OUT/tests/input/$name"; [[ -f "${f%.in}.ans" ]] && cp "${f%.in}.ans" "$OUT/tests/output/$name"
done < <(find "$root/data/secret" -name '*.in' 2>/dev/null | sort)
[[ "$ngroups" == 1 ]] && NOTES+=("grupos/scoring achatados — pontuação por grupo em .kattis.json (curar se for scoring)")

# 7) submissions -> sols
declare -A SMAP=( [accepted]=good [wrong_answer]=wrong [time_limit_exceeded]=slow [run_time_error]=wrong [rejected]=wrong [brute_force]=pass )
for v in accepted wrong_answer time_limit_exceeded run_time_error rejected brute_force; do
  d="$root/submissions/$v"; [[ -d "$d" ]] || continue; mkdir -p "$OUT/sols/${SMAP[$v]}"
  find "$d" -type f ! -name '*.yaml' -exec cp {} "$OUT/sols/${SMAP[$v]}/" \; 2>/dev/null
done
find "$OUT/sols/good" -type f 2>/dev/null | grep -q . || NOTES+=("sem solução accepted")

# 8) output_validator -> bridge scripts/compare.sh
if [[ -d "$root/output_validator" ]]; then
  mkdir -p "$OUT/output_validator" "$OUT/scripts"; cp -a "$root/output_validator/." "$OUT/output_validator/"
  cp "$KT_DIR/validator-bridge.sh" "$OUT/scripts/compare.sh"; chmod +x "$OUT/scripts/compare.sh"
  NOTES+=("checker Kattis instalado via bridge (testlib/C++ exige g++ no juiz)")
fi

# 9) metadados: governança (display_title) p/ a plataforma + sidecar de round-trip
display="$(jq -r --arg p "$MOJ_STATEMENT_LANG" '.name | if type=="object" then (.[$p] // .en // (to_entries|.[0].value // "")) else (.//"") end' <<<"$y")"
[[ -n "$display" ]] || display="$(basename "$OUT")"
jq -n --arg t "$display" '{display_title:$t}' > "$OUT/.moj-meta.json"
jq -n --argjson y "$y" --argjson side "$side" \
  '($side) + {uuid:($y.uuid), source:($y.source), license:($y.license), problem_type:($y.type // "pass-fail"), original_problem_yaml:$y, format:"2025-09"}' > "$OUT/.kattis.json"

printf 'import: %s -> %s%s\n' "$root" "$OUT" "$([[ ${#NOTES[@]} -gt 0 ]] && printf '\n  curadoria: %s' "$(IFS='; '; echo "${NOTES[*]}")")"
