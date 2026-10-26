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

jq --arg uuid "$uuid" --arg id "$ID" --arg lang "$MOJ_STATEMENT_LANG" '
   (.prev) + {uuid:$uuid, moj_id:$id, per_language_tl:.tl, calibrafactor:.calibrafactor, tlmod:.tlmod,
              tl_method:.tl_method, kattis:.kattis, tloverride:.tloverride,
              statement_lang:$lang, format:"2025-09"}' <<<"$collect" > "$PKG/.kattis.json"
