#!/bin/bash
# scripts/compare.sh (gerado pelo import) — BRIDGE do output_validator Kattis p/ o juiz do MOJ.
# O MOJ chama:    compare.sh <team_output> <answer> <input>        -> exit 4=AC 5=PE 6=WA
# O Kattis quer:  <validator> <input> <answer> <feedback_dir> [args] < team_output  -> exit 42=AC 43=WA
# O output_validator/ viaja junto no pacote (../output_validator). Validadores testlib em C++
# precisam de g++ no juiz (roda o ./build uma vez). Validadores simples (sh/py) rodam direto.
set -u
TEAM="${1:?}"; ANS="${2:?}"; IN="${3:?}"; shift 3 2>/dev/null || true
OV="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/output_validator"
[[ -d "$OV" ]] || exit 6
FB="$(mktemp -d)"; trap 'rm -rf "$FB"' EXIT

# build (uma vez) se houver script de build
if [[ -f "$OV/build" ]] && [[ ! -f "$OV/.built" ]]; then ( cd "$OV" && sh ./build ) >/dev/null 2>&1; touch "$OV/.built" 2>/dev/null || true; fi

# descobre como executar: run > a.out/validator > único executável > fonte .py/.sh
RUN=()
if   [[ -f "$OV/run" ]];           then RUN=(sh "$OV/run")
elif [[ -x "$OV/a.out" ]];         then RUN=("$OV/a.out")
elif [[ -x "$OV/validator" ]];     then RUN=("$OV/validator")
else
  exe="$(find "$OV" -maxdepth 1 -type f -executable 2>/dev/null | head -1)"
  if   [[ -n "$exe" ]];            then RUN=("$exe")
  elif f="$(find "$OV" -maxdepth 1 -name '*.py' | head -1)"; [[ -n "$f" ]]; then RUN=(python3 "$f")
  elif f="$(find "$OV" -maxdepth 1 -name '*.sh' | head -1)"; [[ -n "$f" ]]; then RUN=(sh "$f")
  fi
fi
[[ ${#RUN[@]} -gt 0 ]] || exit 6

"${RUN[@]}" "$IN" "$ANS" "$FB" "$@" < "$TEAM" >/dev/null 2>&1; rc=$?
[[ "$rc" == 42 ]] && exit 4
exit 6
