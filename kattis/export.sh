#!/bin/bash
# kattis/export.sh — MOJ -> pacote ICPC/Kattis (2025-09). Não toca no juiz; só converte arquivos.
#   uso: export.sh <pkgdir> <id> <out-dir | out.tar.gz>
#   ex.: export.sh moj-problems/eda2-problems/somaab "eda2-problems#somaab" /tmp/somaab.tar.gz
set -u
KT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; source "$KT_DIR/lib.sh"
PKG="${1:?uso: export.sh <pkgdir> <id> <out>}"; ID="${2:?id}"; OUT="${3:?out}"
[[ -d "$PKG" ]] || { echo "pacote inexistente: $PKG" >&2; exit 1; }
have_py || { echo "preciso de python3 + pyyaml" >&2; exit 1; }
REPO="${ID%%#*}"; PROB="${ID##*#}"
WORK="$(mktemp -d)"; STG="$WORK/$PROB"; mkdir -p "$STG"
trap 'rm -rf "$WORK"' EXIT
NOTES=()   # itens p/ curadoria

# 1) problem.yaml + uuid (reusa o uuid do sidecar se existir, p/ estabilidade)
collect="$(kt_collect "$PKG" "$ID")"
uuid="$(jq -r '.prev.uuid // empty' <<<"$collect")"; [[ -n "$uuid" ]] || uuid="$(kt_uuid "$ID")"
kt_problem_yaml "$collect" "$uuid" "$REPO" > "$STG/problem.yaml" || { echo "falha no problem.yaml" >&2; exit 1; }

# 2) statement/problem.<lang>.md  (md copia; org/tex -> md via pandoc)
mkdir -p "$STG/statement"; ef=""; for e in md org tex; do [[ -f "$PKG/docs/enunciado.$e" ]] && { ef="$e"; break; }; done
SLANG="$MOJ_STATEMENT_LANG"
if [[ "$ef" == md ]]; then cp "$PKG/docs/enunciado.md" "$STG/statement/problem.$SLANG.md"
elif [[ "$ef" == org ]]; then pandoc -f org -t commonmark "$PKG/docs/enunciado.org" -o "$STG/statement/problem.$SLANG.md" 2>/dev/null || cp "$PKG/docs/enunciado.org" "$STG/statement/problem.$SLANG.md"
elif [[ "$ef" == tex ]]; then pandoc -f latex -t commonmark "$PKG/docs/enunciado.tex" -o "$STG/statement/problem.$SLANG.md" 2>/dev/null && NOTES+=("tex->md: revise macros próprias") || { cp "$PKG/docs/enunciado.tex" "$STG/statement/problem.$SLANG.tex"; NOTES+=("tex copiado cru (curar)"); }
else NOTES+=("sem enunciado"); fi
# imagens do docs/
set +o noglob; shopt -s nullglob
for img in "$PKG/docs"/*.{png,jpg,jpeg,svg}; do cp "$img" "$STG/statement/" 2>/dev/null; done
shopt -u nullglob; set -o noglob

# 3) data/{sample,secret}/<name>.{in,ans}
mkdir -p "$STG/data/sample" "$STG/data/secret"
set +o noglob; shopt -s nullglob
ntests=0
for inp in "$PKG/tests/input"/* "$PKG/tests/output"/*; do :; done   # noop p/ nullglob
declare -A SEEN
collect_test(){ local name="$1" dst in="$PKG/tests/input/$1" ans="$PKG/tests/output/$1"
  [[ "$name" == sample* ]] && dst="$STG/data/sample" || dst="$STG/data/secret"
  [[ -f "$in" ]] && cp "$in" "$dst/$name.in" || : > "$dst/$name.in"      # .in vazio se só houver output
  [[ -f "$ans" ]] && cp "$ans" "$dst/$name.ans" || : > "$dst/$name.ans"
  kt_norm_text "$dst/$name.in"; kt_norm_text "$dst/$name.ans"; ntests=$((ntests+1)); }
for f in "$PKG/tests/input"/* "$PKG/tests/output"/*; do n="$(basename "$f")"; [[ -n "${SEEN[$n]:-}" ]] && continue; SEEN[$n]=1; collect_test "$n"; done
shopt -u nullglob; set -o noglob
[[ "$ntests" -gt 0 ]] || NOTES+=("sem testes")
# Kattis: data/sample é o que o solver vê. Se o MOJ não marcou sample*, promove o 1º caso
# (espelha o fallback "1º caso = exemplo" do gen-problem-json).
set +o noglob; shopt -s nullglob
samples=("$STG/data/sample"/*.in)
if [[ ${#samples[@]} -eq 0 ]]; then
  for first in "$STG/data/secret"/*.in; do b="$(basename "$first" .in)"
    mv "$first" "$STG/data/sample/$b.in"; [[ -f "$STG/data/secret/$b.ans" ]] && mv "$STG/data/secret/$b.ans" "$STG/data/sample/$b.ans"
    NOTES+=("sem sample* -> promovi '$b' a data/sample"); break; done
fi
shopt -u nullglob; set -o noglob

# 4) submissions/<veredicto>/  (good/pass->accepted ; wrong->wrong_answer ; slow->time_limit_exceeded)
declare -A VMAP=( [good]=accepted [pass]=accepted [wrong]=wrong_answer [slow]=time_limit_exceeded )
passglobs=()
set +o noglob; shopt -s nullglob
for cat in good pass wrong slow; do
  dstv="${VMAP[$cat]}"; for s in "$PKG/sols/$cat"/*; do [[ -f "$s" ]] || continue
    mkdir -p "$STG/submissions/$dstv"; bn="$(basename "$s")"
    [[ "$cat" == pass ]] && bn="pass_$bn" && passglobs+=("submissions/accepted/$bn")
    cp "$s" "$STG/submissions/$dstv/$bn"; done
done
shopt -u nullglob; set -o noglob
[[ -d "$STG/submissions/accepted" ]] || NOTES+=("sem solução accepted")
if [[ ${#passglobs[@]} -gt 0 ]]; then
  { for g in "${passglobs[@]}"; do printf '%s:\n  use_for_time_limit: false\n' "$g"; done; } > "$STG/submissions/submissions.yaml"
fi

# 5) output_validator/  (se houver compare custom no MOJ) — bridge p/ a interface Kattis (42/43)
CMP=""; for c in "$PKG/scripts/compare.sh"; do [[ -f "$c" ]] && CMP="$c"; done
if [[ -n "$CMP" ]]; then
  mkdir -p "$STG/output_validator"; cp "$CMP" "$STG/output_validator/moj_compare.sh"; chmod +x "$STG/output_validator/moj_compare.sh"
  cat > "$STG/output_validator/run" <<'RUN'
#!/bin/sh
# bridge: Kattis (input answer feedback_dir [args] < team_output, exit 42/43) -> MOJ compare (team answer input, exit 4/5/6)
IN="$1"; ANS="$2"; FB="$3"; t="$(mktemp)"; cat > "$t"
DIR="$(cd "$(dirname "$0")" && pwd)"; sh "$DIR/moj_compare.sh" "$t" "$ANS" "$IN" >/dev/null 2>&1; rc=$?
rm -f "$t"; [ "$rc" = 4 ] || [ "$rc" = 5 ] && exit 42; exit 43
RUN
  chmod +x "$STG/output_validator/run"
  NOTES+=("checker custom convertido (revise portabilidade)")
fi

# 6) input_validators/  (obrigatório no Kattis) — trivial accept-all
mkdir -p "$STG/input_validators/accept_all"
printf '#!/bin/sh\ncat >/dev/null 2>&1\nexit 42\n' > "$STG/input_validators/accept_all/run"; chmod +x "$STG/input_validators/accept_all/run"
NOTES+=("input_validator trivial (accept-all) — escreva um real p/ rigor ICPC")

# 7) sidecar .kattis.json (round-trip sem perda) — guarda no pacote MOJ E no export
side="$(jq -n --arg uuid "$uuid" --arg id "$ID" --argjson tl "$(jq '.tl' <<<"$collect")" \
  --arg cf "$(jq -r '.calibrafactor' <<<"$collect")" --argjson tlmod "$(jq '.tlmod' <<<"$collect")" \
  --arg lang "$SLANG" --argjson custom_checker "$([[ -n "$CMP" ]] && echo true || echo false)" \
  '{uuid:$uuid, moj_id:$id, per_language_tl:$tl, calibrafactor:$cf, tlmod:$tlmod, statement_lang:$lang, custom_checker:$custom_checker, format:"2025-09"}')"
printf '%s\n' "$side" > "$STG/.kattis.json"   # viaja no pacote exportado (round-trip); não mexe na fonte MOJ

# 8) saída: diretório ou arquivo
if [[ "$OUT" == *.tar.gz || "$OUT" == *.tgz || "$OUT" == *.kpp ]]; then
  tar -C "$WORK" -czf "$OUT" "$PROB"
elif [[ "$OUT" == *.zip ]]; then ( cd "$WORK" && zip -qr "$OUT" "$PROB" ) 2>/dev/null || tar -C "$WORK" -czf "${OUT%.zip}.tar.gz" "$PROB"
else mkdir -p "$OUT"; cp -a "$STG/." "$OUT/"; fi
printf 'export: %s -> %s  (%d testes)%s\n' "$ID" "$OUT" "$ntests" "$([[ ${#NOTES[@]} -gt 0 ]] && printf '\n  curadoria: %s' "$(IFS='; '; echo "${NOTES[*]}")")"
