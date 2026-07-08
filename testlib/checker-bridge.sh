#!/bin/bash
# scripts/compare.sh (instalado por mojtools/testlib/install-checker.sh) — BRIDGE de um
# checker TESTLIB PADRÃO para o contrato do juiz do MOJ.
#
# O MOJ chama:      compare.sh <team_output> <answer> <input>       -> exit 4=AC 5=AC,PE 6=WA (outros=UE)
# O testlib quer:   checker <input> <team_output> <answer>          -> exit 0=ok 1=wa 2=pe 3=fail
#                                                                      (4=dirt 7=points 8=eof-inesperado)
# ATENÇÃO à semântica: o _pe da testlib ("saída fora do formato esperado/não parseável")
# NÃO é o PE do MOJ/BOCA ("resposta certa, só espaçamento difere" — aceito). _pe da
# testlib é resposta ERRADA => Wrong Answer, SEMPRE (idem _dirt e eof inesperado).
# O fonte viaja no pacote (scripts/checker.cpp, testlib PADRÃO — sem -DBOCA_SUPPORT); o
# testlib.h vem VENDORADO no mojtools (testlib/testlib.h; um scripts/testlib.h local, se
# existir, tem precedência). Compila no HOST do juiz na 1ª comparação (o compare roda FORA
# da jaula) e cacheia o binário FORA de scripts/ (não entra no tl-checksum). Requer g++ no
# host; fallback: g++ do rootfs (CAGE_ROOT) via bwrap, com -static. Guia de autoria:
# mojtools/docs/checker-testlib.md.
set -u
TEAM="${1:?}"; ANS="${2:?}"; IN="${3:?}"

PKG="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"
SRC="$PKG/scripts/checker.cpp"
[[ -f "$SRC" ]] || { echo "checker-bridge: scripts/checker.cpp não existe no pacote"; exit 7; }

# testlib.h: override do pacote > vendorado do mojtools (o build-and-test roda o compare
# com CWD = diretório do mojtools; MOJTOOLS_DIR sobrepõe p/ testes fora do juiz)
MOJTOOLS_DIR="${MOJTOOLS_DIR:-$PWD}"
TESTLIB="$PKG/scripts/testlib.h"
[[ -f "$TESTLIB" ]] || TESTLIB="$MOJTOOLS_DIR/testlib/testlib.h"
[[ -f "$TESTLIB" ]] || { echo "checker-bridge: testlib.h não encontrado (nem em scripts/ nem em $MOJTOOLS_DIR/testlib/)"; exit 7; }

# cache do binário FORA de scripts/ (o tl-checksum cobre scripts/*: binário lá dentro
# divergiria o checksum do juiz do do servidor). Chave = fonte + testlib + compilador.
CACHE="$PKG/.checker-cache"
HASH="$(cat "$SRC" "$TESTLIB" <(g++ --version 2>/dev/null || true) 2>/dev/null | sha256sum | cut -c1-16)"
BIN="$CACHE/checker.$HASH"

if [[ ! -x "$BIN" ]]; then
  mkdir -p "$CACHE" 2>/dev/null
  find "$CACHE" -maxdepth 1 -name 'checker.*' -delete 2>/dev/null   # versões antigas
  if command -v g++ >/dev/null 2>&1; then
    g++ -O2 -std=gnu++17 -o "$BIN.tmp" "$SRC" -I "$(dirname "$TESTLIB")" 2> "$CACHE/compile.log" \
      || { echo "checker-bridge: falha ao compilar o checker (g++ do host):"; cat "$CACHE/compile.log"; exit 7; }
  elif [[ -n "${CAGE_ROOT:-}" && -x "$CAGE_ROOT/usr/bin/g++" ]] && command -v bwrap >/dev/null 2>&1; then
    # sem g++ no host: compila com o do rootfs, ESTÁTICO (o binário roda no host)
    bwrap --die-with-parent --ro-bind "$CAGE_ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
          --bind "$PKG" "$PKG" --chdir "$PKG" \
          /usr/bin/g++ -O2 -std=gnu++17 -static -o "$BIN.tmp" "$SRC" -I "$(dirname "$TESTLIB")" \
          2> "$CACHE/compile.log" \
      || { echo "checker-bridge: falha ao compilar o checker (g++ do rootfs):"; cat "$CACHE/compile.log"; exit 7; }
  else
    echo "checker-bridge: nenhum g++ disponível (host sem g++ e sem CAGE_ROOT com toolchain)"; exit 7
  fi
  mv -f "$BIN.tmp" "$BIN" && chmod +x "$BIN"
fi

# executa na interface PADRÃO do testlib; a mensagem do checker (stderr) vai p/ o log .compare
"$BIN" "$IN" "$TEAM" "$ANS"; rc=$?
case "$rc" in
  0)     exit 4 ;;   # _ok                        -> Accepted
  1|2|4|8) exit 6 ;; # _wa/_pe/_dirt/eof          -> Wrong Answer (o _pe da testlib é
                     #   "formato inválido/não parseável" = resposta errada; não confundir
                     #   com o AC,PE do MOJ, que é exclusivo do comparador diff default)
  3) echo "checker-bridge: checker devolveu _fail (rc=3) — gabarito/checker inválido"; exit 7 ;;
  7) echo "checker-bridge: checker devolveu _points (rc=7) — parcial por checker NÃO é suportado (use grupos em tests/score)"; exit 7 ;;
  *) echo "checker-bridge: exit inesperado do checker (rc=$rc)"; exit 7 ;;
esac
