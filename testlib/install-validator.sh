#!/bin/bash
# install-validator.sh <pkgdir> [<validator.cpp>] — instala e RODA o validador de entrada (testlib) na
# máquina do autor. Com o arquivo: copia para scripts/validator.cpp. Sem ele: só roda o que o pacote já
# tem. Em seguida compila (com o g++ daqui) e roda sobre cada tests/input/*, pelo MESMO
# testlib/validator-run.sh que a calibração usa no juiz — o resultado local é o que o juiz vai dizer.
# Atalho da CLI: `moj validator [<dir>] [<validator.cpp>]`. Guia: mojtools/docs/validador-testlib.md
# Saída: 0 = todas as entradas passaram; 1 = alguma inválida; 2 = o validador não rodou / uso errado.
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PKG="${1:?uso: install-validator.sh <pkgdir> [<validator.cpp>]}"
SRC="${2:-}"
PKG="$(cd "$PKG" 2>/dev/null && pwd)" || { echo "ERRO: pacote não existe: $1" >&2; exit 2; }
[[ -d "$PKG/tests/input" || -f "$PKG/conf" ]] || { echo "ERRO: $PKG não parece um pacote MOJ" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERRO: falta o jq" >&2; exit 2; }

if [[ -n "$SRC" ]]; then
  [[ -f "$SRC" ]] || { echo "ERRO: validador não encontrado: $SRC" >&2; exit 2; }
  grep -q 'registerValidation' "$SRC" || echo "aviso: $SRC não chama registerValidation(argc, argv) — a testlib não confere nada assim" >&2
  mkdir -p "$PKG/scripts"
  [[ "$(readlink -f "$SRC")" == "$(readlink -f "$PKG/scripts/validator.cpp" 2>/dev/null)" ]] || cp "$SRC" "$PKG/scripts/validator.cpp"
  echo "instalado: scripts/validator.cpp"
fi
[[ -f "$PKG/scripts/validator.cpp" ]] || { echo "ERRO: o pacote não tem scripts/validator.cpp (passe o arquivo: install-validator.sh <dir> validator.cpp)" >&2; exit 2; }
# testlib.h igual ao vendorado não precisa viajar no pacote (o do mojtools é usado)
if [[ -f "$PKG/scripts/testlib.h" ]] && cmp -s "$PKG/scripts/testlib.h" "$HERE/testlib.h"; then
  echo "aviso: scripts/testlib.h é igual ao vendorado do mojtools — pode apagar (o juiz usa o do mojtools)"
fi

J="$(bash "$HERE/validator-run.sh" "$PKG")" || { echo "ERRO: validator-run.sh falhou" >&2; exit 2; }
v="$(jq -r .verdict <<<"$J")"
jq -r '.tests[] | "  \(if .code == "OK" then "✓" else "✗" end) \(.name)\(if .code != "OK" then " — \(.code): \(.msg)" else "" end)"' <<<"$J"
case "$v" in
  ok)      echo "validador: todas as $(jq '.tests|length' <<<"$J") entradas passaram"; exit 0 ;;
  invalid) echo "validador: $(jq '[.tests[]|select(.code=="INVALID")]|length' <<<"$J") de $(jq '.tests|length' <<<"$J") entradas INVÁLIDAS"; exit 1 ;;
  *)       echo "validador: não rodou direito ($v) — veja as mensagens acima"; exit 2 ;;
esac
