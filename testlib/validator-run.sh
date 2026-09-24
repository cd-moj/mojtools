#!/bin/bash
# mojtools/testlib/validator-run.sh <pkgdir> — roda o VALIDADOR DE ENTRADA do pacote (scripts/validator.cpp,
# testlib `registerValidation`, o padrão do Polygon) sobre cada tests/input/* e imprime UMA linha JSON no
# formato de uma entrada do .calib-sols.json:
#   {file:"scripts/validator.cpp", lang:"cpp", category:"validator", verdict:"none"|"ok"|"invalid"|"error",
#    tests:[{name, code:"OK"|"INVALID"|"FAIL", msg}]}
#   none    = o pacote não tem validador;
#   ok      = todas as entradas passaram;
#   invalid = alguma entrada foi reprovada (a testlib saiu com _fail = 3; `msg` é a mensagem dela);
#   error   = o validador não compilou, travou/estourou o tempo ou o orçamento acabou (`msg` diz o quê).
# Quem chama: calibreitor.sh (calibração COMPLETA, no juiz — o agente sobe o `sols` inteiro, então o
# servidor recebe esta linha sem mudança no agente) e install-validator.sh (na máquina do autor).
# Pedido da banca via Arthur Botelho (22/09/2026); caso real: um teste com n=1296 num problema de N<=1000
# fez a "saída esperada" ser lixo de estouro de vetor (edson-1179).
#
# Confiança: o validador é código do AUTOR e roda no HOST do juiz, como o checker testlib e o compare.sh
# (que já rodam lá). Freios: timeout por entrada (VALIDATOR_TL, 5 s), memória (4 GB de endereço) e um
# ORÇAMENTO total (VALIDATOR_BUDGET, 60 s, compilação incluída) — um validador em laço infinito não pode
# comer o teto de wall-clock da calibração e deixar o problema sem TL.
# A compilação segue a da testlib/checker-bridge.sh (g++ do host; sem ele, o g++ da rootfs em bwrap,
# ESTÁTICO). É uma segunda cópia de propósito: a bridge roda em ~200 pacotes de produção e não tem teste
# da rota bwrap — unificar as duas pede esse teste antes. Mexeu numa, confira a outra.
set -u
PKG="${1:?uso: validator-run.sh <pkgdir>}"
PKG="$(cd "$PKG" 2>/dev/null && pwd)" || { echo "validator-run: pacote não existe: $1" >&2; exit 2; }
TL="${VALIDATOR_TL:-5}"; BUDGET="${VALIDATOR_BUDGET:-60}"
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SRC="$PKG/scripts/validator.cpp"
emit(){ # <verdict> <arquivo TSV name\tcode\tmsg | vazio>
  if [[ -s "${2:-}" ]]; then
    jq -Rsc --arg v "$1" '{file:"scripts/validator.cpp", lang:"cpp", category:"validator", verdict:$v,
      tests:[split("\n")[] | select(length > 0) | split("\t") | {name:.[0], code:.[1], msg:(.[2] // "")}]}' < "$2"
  else
    jq -cn --arg v "$1" '{file:"scripts/validator.cpp", lang:"cpp", category:"validator", verdict:$v, tests:[]}'
  fi; }
one_line(){ tr '\t\r\n' '   ' | cut -c1-300; }   # mensagem p/ uma célula do TSV
# PORTÁVEL p/ a máquina do autor (macOS: sem GNU coreutils não há flock/timeout/sha256sum)
_sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
_TO=""; if command -v timeout >/dev/null 2>&1; then _TO=timeout; elif command -v gtimeout >/dev/null 2>&1; then _TO=gtimeout; fi
_to(){ local s="$1"; shift; if [[ -n "$_TO" ]]; then "$_TO" -k 1 "$s" "$@"; else "$@"; fi; }
[[ -f "$SRC" ]] || { emit none; exit 0; }
START=$SECONDS
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# testlib.h: o do pacote (scripts/testlib.h) vence o vendorado do mojtools
TESTLIB="$PKG/scripts/testlib.h"; [[ -f "$TESTLIB" ]] || TESTLIB="$HERE/testlib.h"
CFLAGS=(-O2 -std=gnu++17 -include cassert -include cstring -include cstdint)
# cache FORA de scripts/ (o tl-checksum cobre scripts/*): chave = fonte + testlib + compilador
CACHE="$PKG/.validator-cache"
ROOTFS_CC=""
[[ -n "${CAGE_ROOT:-}" && -x "$CAGE_ROOT/usr/bin/g++" ]] && ROOTFS_CC="$CAGE_ROOT $(stat -c %Y "$CAGE_ROOT/usr/bin/g++" 2>/dev/null)"
HASH="$(cat "$SRC" "$TESTLIB" <(g++ --version 2>/dev/null || true) <(printf '%s\n' "$ROOTFS_CC") 2>/dev/null | _sha | cut -c1-16)"
BIN="$CACHE/validator.$HASH"
if [[ ! -x "$BIN" ]]; then
  mkdir -p "$CACHE" 2>/dev/null
  {
    command -v flock >/dev/null 2>&1 && flock 9 2>/dev/null   # vários slots do juiz; no Mac não há flock
    if [[ ! -x "$BIN" ]]; then
      find "$CACHE" -maxdepth 1 -name 'validator.*' -delete 2>/dev/null
      if command -v g++ >/dev/null 2>&1; then
        _to "$BUDGET" g++ "${CFLAGS[@]}" -o "$CACHE/validator.new" "$SRC" -I "$(dirname "$TESTLIB")" 2> "$CACHE/compile.log"
      elif [[ -n "$ROOTFS_CC" ]] && command -v bwrap >/dev/null 2>&1; then
        # tudo SOB /tmp (o --tmpfs): a rootfs é montada READ-ONLY em / (ver checker-bridge.sh)
        _to "$BUDGET" bwrap --die-with-parent --ro-bind "$CAGE_ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
              --setenv TMPDIR /tmp \
              --ro-bind "$SRC" /tmp/validator.cpp --ro-bind "$TESTLIB" /tmp/testlib.h \
              --bind "$CACHE" /tmp/out --chdir /tmp \
              /usr/bin/g++ "${CFLAGS[@]}" -static -o /tmp/out/validator.new /tmp/validator.cpp -I /tmp \
              2> "$CACHE/compile.log"
      else
        echo "nenhum g++ disponível (host sem g++ e sem CAGE_ROOT com toolchain)" > "$CACHE/compile.log"; false
      fi && mv -f "$CACHE/validator.new" "$BIN" && chmod +x "$BIN"
    fi
  } 9>"$CACHE/.lock"
fi
if [[ ! -x "$BIN" ]]; then
  printf '%s\t%s\t%s\n' "scripts/validator.cpp" FAIL "não compilou: $(grep -m1 -E 'error|erro' "$CACHE/compile.log" 2>/dev/null | one_line)" > "$W/r.tsv"
  emit error "$W/r.tsv"; exit 0
fi

# uma entrada por vez, em ordem de nome
bad=0; fail=0
while IFS= read -r f; do
  name="${f##*/}"
  if (( SECONDS - START >= BUDGET )); then
    printf '%s\t%s\t%s\n' "$name" FAIL "orçamento de ${BUDGET}s do validador esgotado — não conferido" >> "$W/r.tsv"; ((fail++)); continue
  fi
  ( ulimit -v 4194304 2>/dev/null; _to "$TL" "$BIN" ) < "$f" > /dev/null 2> "$W/err"; rc=$?
  case "$rc" in
    0) printf '%s\tOK\t\n' "$name" >> "$W/r.tsv" ;;
    3) printf '%s\tINVALID\t%s\n' "$name" "$(head -c 600 "$W/err" | one_line)" >> "$W/r.tsv"; ((bad++)) ;;
    124|137) printf '%s\tFAIL\t%s\n' "$name" "o validador passou de ${TL}s nesta entrada" >> "$W/r.tsv"; ((fail++)) ;;
    *) printf '%s\tFAIL\t%s\n' "$name" "o validador saiu com código $rc: $(head -c 400 "$W/err" | one_line)" >> "$W/r.tsv"; ((fail++)) ;;
  esac
done < <(find "$PKG/tests/input" -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort)
if (( fail > 0 )); then emit error "$W/r.tsv"
elif (( bad > 0 )); then emit invalid "$W/r.tsv"
else emit ok "$W/r.tsv"; fi
