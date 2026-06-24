#!/bin/bash
# kattis/sidecar.sh — escreve problem.yaml + .kattis.json DENTRO do pacote MOJ, tornando-o
# "Kattis-aware" sem mover testes/soluções (a convergência incremental). Idempotente;
# preserva o uuid existente. Best-effort: sem python3+pyyaml, não faz nada (exit 0).
#   uso: sidecar.sh <pkgdir> <id> [repo]
set -u
KT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; source "$KT_DIR/lib.sh"
PKG="${1:?uso: sidecar.sh <pkgdir> <id> [repo]}"; ID="${2:?id}"; REPO="${3:-${ID%%#*}}"
[[ -d "$PKG" ]] || exit 0
have_py || exit 0

collect="$(kt_collect "$PKG" "$ID")"
uuid="$(jq -r '.prev.uuid // empty' <<<"$collect")"; [[ -n "$uuid" ]] || uuid="$(kt_uuid "$ID")"
kt_problem_yaml "$collect" "$uuid" "$REPO" > "$PKG/problem.yaml" 2>/dev/null || { rm -f "$PKG/problem.yaml"; exit 0; }

jq -n --arg uuid "$uuid" --arg id "$ID" --argjson tl "$(jq '.tl' <<<"$collect")" \
   --arg cf "$(jq -r '.calibrafactor' <<<"$collect")" --argjson tlmod "$(jq '.tlmod' <<<"$collect")" \
   --arg lang "$MOJ_STATEMENT_LANG" --argjson prev "$(jq '.prev' <<<"$collect")" '
   ($prev) + {uuid:$uuid, moj_id:$id, per_language_tl:$tl, calibrafactor:$cf, tlmod:$tlmod,
              statement_lang:$lang, format:"2025-09"}' > "$PKG/.kattis.json"
