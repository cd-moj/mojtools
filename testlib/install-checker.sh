#!/bin/bash
# install-checker.sh <pkgdir> <checker.cpp> — NORMALIZA um problema p/ usar checker
# testlib no MOJ: instala o fonte como scripts/checker.cpp + a bridge como
# scripts/compare.sh (substituindo binário ELF legado, se houver) e roda um smoke.
# Semântica: _ok=Accepted; _wa/_pe/_dirt/eof=Wrong Answer (o _pe da testlib é formato
# inválido = errado, não é o AC,PE do MOJ); _fail/_points=erro de juiz.
# Guia de autoria: mojtools/docs/checker-testlib.md
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

PKG="${1:?uso: install-checker.sh <pkgdir> <checker.cpp>}"
SRC="${2:?uso: install-checker.sh <pkgdir> <checker.cpp>}"
PKG="$(cd "$PKG" && pwd)"
[[ -f "$SRC" ]] || { echo "ERRO: checker não encontrado: $SRC" >&2; exit 1; }
[[ -d "$PKG/tests/input" || -f "$PKG/conf" ]] || { echo "ERRO: $PKG não parece um pacote MOJ" >&2; exit 1; }

mkdir -p "$PKG/scripts"

# binário ELF legado no lugar do compare.sh? substitui (é exatamente o que normalizamos)
if [[ -f "$PKG/scripts/compare.sh" ]] && file -b "$PKG/scripts/compare.sh" 2>/dev/null | grep -q ELF; then
  echo "aviso: scripts/compare.sh era um binário ELF ($(du -h "$PKG/scripts/compare.sh" | cut -f1)) — substituído pela bridge"
fi

cp "$SRC" "$PKG/scripts/checker.cpp"
cp "$HERE/checker-bridge.sh" "$PKG/scripts/compare.sh"
chmod +x "$PKG/scripts/compare.sh"

[[ -f "$PKG/scripts/testlib.h" ]] && \
  echo "aviso: scripts/testlib.h local existe e TEM PRECEDÊNCIA sobre o vendorado ($HERE/testlib.h) — mantenha só se for intencional"

# smoke: gabarito contra ele mesmo tem de ser Accepted (exit 4)
# `| head -1` fecha o pipe cedo; com muitos testes o `sort` ainda escrevendo
# leva SIGPIPE (rc=141) e o `pipefail` do topo do script aborta o instalador
# --- determinístico (não flake) em pacotes com centenas de testes. O
# `|| true` interno absorve o SIGPIPE sem mascarar erro real (find/sort vazio
# só resulta em `first` vazio, tratado abaixo).
first="$(find "$PKG/tests/input" -maxdepth 1 -type f 2>/dev/null | LC_ALL=C sort | head -1 || true)"
if [[ -n "$first" ]]; then
  name="$(basename "$first")"; exp="$PKG/tests/output/$name"
  if [[ -f "$exp" ]]; then
    rc=0; ( cd "$HERE/.." && "$PKG/scripts/compare.sh" "$exp" "$exp" "$first" ) >/dev/null 2>&1 || rc=$?
    if [[ "$rc" == 4 ]]; then
      echo "smoke OK: gabarito x gabarito no teste '$name' => Accepted (exit 4)"
    else
      echo "ERRO no smoke: gabarito x gabarito no teste '$name' => exit $rc (esperado 4)." >&2
      echo "  Rode à mão p/ ver o log: (cd $HERE/.. && $PKG/scripts/compare.sh $exp $exp $first)" >&2
      exit 1
    fi
  fi
fi

echo "instalado: scripts/checker.cpp + scripts/compare.sh (bridge testlib)"
echo "lembrete: 'moj push' NÃO carrega scripts/ — transporte o pacote com 'moj upload <id> <tar.gz>'."
