#!/bin/bash
# install-checker.sh <pkgdir> <checker.cpp> — NORMALIZA um problema p/ usar checker testlib
# no MOJ: instala o fonte como scripts/checker.cpp + o STUB como scripts/compare.sh
# (substituindo binário ELF legado ou uma cópia antiga da bridge, se houver) e roda um smoke.
#
# O pacote leva SÓ o fonte + o stub: o BRIDGE e o testlib.h moram no mojtools (fonte única —
# ver testlib/compare-stub.sh e testlib/checker-bridge.sh).
# Semântica: _ok=Accepted; _wa/_pe/_dirt/eof=Wrong Answer (o _pe da testlib é formato
# inválido = errado, não é o AC,PE do MOJ); _fail/_points=erro de juiz.
# Guia de autoria: mojtools/docs/checker-testlib.md
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
MOJT="$(cd "$HERE/.." && pwd)"

PKG="${1:?uso: install-checker.sh <pkgdir> <checker.cpp>}"
SRC="${2:?uso: install-checker.sh <pkgdir> <checker.cpp>}"
PKG="$(cd "$PKG" && pwd)"
[[ -f "$SRC" ]] || { echo "ERRO: checker não encontrado: $SRC" >&2; exit 1; }
[[ -d "$PKG/tests/input" || -f "$PKG/conf" ]] || { echo "ERRO: $PKG não parece um pacote MOJ" >&2; exit 1; }

mkdir -p "$PKG/scripts"

# o que havia no lugar do compare.sh? (binário ELF legado / cópia antiga da bridge)
if [[ -f "$PKG/scripts/compare.sh" ]]; then
  if file -b "$PKG/scripts/compare.sh" 2>/dev/null | grep -q ELF; then
    echo "aviso: scripts/compare.sh era um binário ELF ($(du -h "$PKG/scripts/compare.sh" | cut -f1)) — substituído pelo stub"
  elif grep -q 'checker\.cpp' "$PKG/scripts/compare.sh" 2>/dev/null; then
    echo "aviso: scripts/compare.sh era uma CÓPIA da bridge — substituída pelo stub (a bridge agora é única, no mojtools)"
  fi
fi

[[ "$(readlink -f "$SRC")" == "$(readlink -f "$PKG/scripts/checker.cpp" 2>/dev/null)" ]] \
  || cp "$SRC" "$PKG/scripts/checker.cpp"
cp "$HERE/compare-stub.sh" "$PKG/scripts/compare.sh"
chmod +x "$PKG/scripts/compare.sh"     # o juiz EXECUTA o compare direto: sem +x é UE em todo teste

# testlib.h dentro do pacote: 190KB inúteis (o bridge usa o do mojtools). Se for o MESMO
# arquivo, sai fora; se foi modificado, fica — mas AVISA, porque ele TEM PRECEDÊNCIA.
if [[ -f "$PKG/scripts/testlib.h" ]]; then
  if cmp -s "$PKG/scripts/testlib.h" "$HERE/testlib.h"; then
    rm -f "$PKG/scripts/testlib.h"
    echo "removido: scripts/testlib.h (idêntico ao vendorado do mojtools — o pacote não precisa carregá-lo)"
  else
    echo "aviso: scripts/testlib.h local DIFERE do vendorado e TEM PRECEDÊNCIA — mantenha só se for intencional"
  fi
fi

# smoke: gabarito contra ele mesmo tem de ser Accepted (exit 4) — exercita o bridge de verdade
# (compila o checker). `| head -1` fecha o pipe cedo; com muitos testes o `sort` ainda escrevendo
# leva SIGPIPE (rc=141) e o `pipefail` do topo abortaria o instalador --- o `|| true` absorve.
first="$(find "$PKG/tests/input" -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort | head -1 || true)"
if [[ -n "$first" ]]; then
  name="$(basename "$first")"; exp="$PKG/tests/output/$name"
  if [[ -f "$exp" ]]; then
    rc=0
    ( cd "$MOJT" && MOJTOOLS_DIR="$MOJT" "$PKG/scripts/compare.sh" "$exp" "$exp" "$first" ) >/dev/null 2>&1 || rc=$?
    if [[ "$rc" == 4 ]]; then
      echo "smoke OK: gabarito x gabarito no teste '$name' => Accepted (exit 4)"
    else
      echo "ERRO no smoke: gabarito x gabarito no teste '$name' => exit $rc (esperado 4)." >&2
      echo "  Rode à mão p/ ver o log: (cd $MOJT && MOJTOOLS_DIR=$MOJT $PKG/scripts/compare.sh $exp $exp $first)" >&2
      exit 1
    fi
  fi
fi

echo "instalado: scripts/checker.cpp + scripts/compare.sh (stub -> mojtools/testlib/checker-bridge.sh)"
echo "lembrete: 'moj push' carrega o scripts/ (round-trip completo); 'moj upload <id> <tar.gz>' sobe o pacote inteiro."
