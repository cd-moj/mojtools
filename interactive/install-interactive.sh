#!/bin/bash
# install-interactive.sh <pkgdir> <arbitro.{cpp,cc,py,sh}> [--score] [--langs "c cpp py sh"]
#   [--keep-compare]
# NORMALIZA um problema INTERATIVO do MOJ: instala o árbitro em scripts/, o DRIVER comum
# (prep.sh+run.sh) em scripts/c/ com symlinks p/ as demais linguagens, o compare genérico
# do protocolo e (com --score) o summary de ranking. Tutorial:
# mojtools/docs/problema-interativo.md
#   --score        : problema de RANKING — instala scripts/summary.sh (soma dos SCOREs)
#   --langs "..."  : restringe as linguagens com driver (default: TODAS as de mojtools/lang
#                    — linguagem SEM o driver julgaria NÃO-interativamente, errado)
#   --keep-compare : preserva um scripts/compare.sh custom já existente
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

USO='uso: install-interactive.sh <pkgdir> <arbitro.cpp|.py|.sh> [--score] [--langs "..."]'
PKG="${1:?$USO}"
SRC="${2:?$USO}"
shift 2
SCORE=0; KEEPCMP=0; LANGS=""
while [[ $# -gt 0 ]]; do case "$1" in
  --score) SCORE=1; shift;;
  --keep-compare) KEEPCMP=1; shift;;
  --langs) LANGS="${2:?--langs precisa da lista}"; shift 2;;
  *) echo "opção desconhecida: $1" >&2; exit 1;;
esac; done

PKG="$(cd "$PKG" && pwd)"
[[ -f "$SRC" ]] || { echo "ERRO: árbitro não encontrado: $SRC" >&2; exit 1; }
[[ -d "$PKG/tests/input" || -f "$PKG/conf" ]] || { echo "ERRO: $PKG não parece um pacote MOJ" >&2; exit 1; }
ext="${SRC##*.}"
case "$ext" in cpp|cc|py|sh) ;; *) echo "ERRO: árbitro deve ser .cpp/.cc/.py/.sh (ou adapte scripts/arbitro à mão)" >&2; exit 1;; esac

# COMPOSIÇÃO: o interativo OCUPA a execução por linguagem (scripts/<lang> vira symlink p/ c)
# e tem compare próprio — NÃO compõe com submissão-de-função nem com checker testlib
# (ver docs/correcao-especial.md, "slots"). compile.sh real no caminho = conflito.
if compgen -G "$PKG/scripts/*/compile.sh" >/dev/null 2>&1; then
  echo "AVISO: este pacote tem scripts/<lang>/compile.sh (submissão de função/ban?)." >&2
  echo "       Interativo × submissão-de-função NÃO compõem: o interativo controla a" >&2
  echo "       execução por linguagem. Langs com dir real serão MANTIDAS (sem symlink) —" >&2
  echo "       confira se é isso que você quer." >&2
fi

mkdir -p "$PKG/scripts/c"

# árbitro no nível de scripts/ (o prep.sh procura arbitro.{cpp,cc,py,sh} lá)
[[ "$(readlink -f "$SRC")" != "$(readlink -f "$PKG/scripts/arbitro.$ext" 2>/dev/null)" ]] \
  && cp "$SRC" "$PKG/scripts/arbitro.$ext"

# driver comum em scripts/c/, symlink de diretório p/ as outras linguagens.
#   prep.sh -> STUB (roda NO HOST: o build-and-test dá source nele; o de verdade mora no mojtools)
#   run.sh  -> CÓPIA REAL (entra NA JAULA: o cage-run monta o arquivo como /tmp/script e o
#              executa lá dentro — um stub não enxergaria o mojtools)
cp "$HERE/prep-stub.sh" "$PKG/scripts/c/prep.sh"
cp "$HERE/run.sh"       "$PKG/scripts/c/run.sh"
chmod +x "$PKG/scripts/c/prep.sh" "$PKG/scripts/c/run.sh"   # prep é testado com -x!

[[ -n "$LANGS" ]] || LANGS="$(find "$HERE/../lang" -maxdepth 1 \( -type d -o -type l \) -printf '%f\n' 2>/dev/null | grep -v '^lang$' | LC_ALL=C sort | paste -sd' ' -)"
linked=""
for l in $LANGS; do
  [[ "$l" == c ]] && continue
  if [[ -e "$PKG/scripts/$l" && ! -L "$PKG/scripts/$l" ]]; then
    echo "aviso: scripts/$l existe e NÃO é symlink — mantido (confira se é interativo!)" >&2
    continue
  fi
  ln -sfn c "$PKG/scripts/$l"
  linked+=" $l"
done

# compare genérico do protocolo (13/6/4 + SCORE=) — STUB (roda no host)
if [[ -f "$PKG/scripts/compare.sh" && "$KEEPCMP" == 1 ]]; then
  echo "aviso: scripts/compare.sh existente PRESERVADO (--keep-compare)"
else
  [[ -f "$PKG/scripts/compare.sh" ]] && echo "aviso: scripts/compare.sh existente foi substituído pelo genérico"
  cp "$HERE/compare-stub.sh" "$PKG/scripts/compare.sh"
  chmod +x "$PKG/scripts/compare.sh"
fi

# summary de ranking (opcional) — STUB (é SOURCED no host)
if (( SCORE )); then
  [[ -f "$PKG/scripts/summary.sh" ]] && echo "aviso: scripts/summary.sh existente foi substituído pelo de ranking"
  cp "$HERE/summary-stub.sh" "$PKG/scripts/summary.sh"
  chmod +x "$PKG/scripts/summary.sh"
fi

# conf: só AVISA (não edita) sobre o que interativo costuma precisar
conf="$PKG/conf"
grep -q 'ULIMITS\[-u\]' "$conf" 2>/dev/null || \
  echo "aviso: conf sem ULIMITS[-u] — interativo roda 2+ processos; recomende ULIMITS[-u]=10000"
grep -q 'TLMOD\[calibrafactor\]' "$conf" 2>/dev/null || \
  echo "aviso: conf sem TLMOD[calibrafactor] — o tempo do ÁRBITRO entra no TL; calibre com folga (ex.: TLMOD[calibrafactor]=\"10+1.5\")"

# smoke: prep materializa o árbitro num dir temporário? (compila o .cpp na hora, pelo bridge
# do mojtools — o MOJTOOLS_DIR é o que o stub usa p/ achá-lo, igual ao build-and-test)
MOJT="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PROBLEMTEMPLATEDIR="$PKG" EXTRABINDINGS="" MOJTOOLS_DIR="$MOJT" \
  bash -c "source '$PKG/scripts/c/prep.sh' '$T'" || true
if [[ -x "$T/arbitro" ]]; then
  echo "smoke OK: prep materializou o árbitro ($(file -b "$T/arbitro" | cut -d, -f1))"
else
  echo "ERRO no smoke: prep NÃO materializou \$workdir/arbitro — veja mensagens acima" >&2
  exit 1
fi

echo "instalado: scripts/arbitro.$ext + driver (c +symlinks:$linked) + compare$( ((SCORE)) && echo ' + summary(rank)' )"
echo "lembrete: 'moj push' carrega o scripts/ (round-trip completo, symlinks inclusive); 'moj upload <id> <tar.gz>' sobe o pacote inteiro."
