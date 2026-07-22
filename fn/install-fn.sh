#!/bin/bash
# install-fn.sh <pkgdir> [--langs "c cpp py java rs"] — instala os DRIVERS de submissão de
# função no pacote (scripts/<lang>/compile.sh, cópia real +x — o compile roda NA JAULA, onde
# o mojtools não existe). Fonte única: script-templates/submissao-de-funcao/files/ (o mesmo
# template do editor web). Depois de instalar, EDITE as zonas EDIT-ME de cada driver
# (protótipo, leitura, chamada) e lembre da SENTINELA: a última linha de todo tests/input/*
# é 424242. Guia completo: docs/submissao-de-funcao.md
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TPL="$HERE/../script-templates/submissao-de-funcao/files"

pkg="${1:?uso: install-fn.sh <pkgdir> [--langs \"c cpp py java rs\"]}"; shift || true
[[ -d "$pkg" ]] || { echo "install-fn: pacote inexistente: $pkg" >&2; exit 1; }
langs="c cpp py java rs"
while [[ $# -gt 0 ]]; do case "$1" in
  --langs) langs="${2//,/ }"; shift 2;;
  *) echo "install-fn: opção desconhecida: $1" >&2; exit 1;;
esac; done

n=0
for l in $langs; do
  [[ -f "$TPL/$l/compile.sh" ]] || { echo "  ⚠ sem template p/ linguagem '$l' (tem: c cpp py java rs) — pulada" >&2; continue; }
  mkdir -p "$pkg/scripts/$l"
  cp "$TPL/$l/compile.sh" "$pkg/scripts/$l/compile.sh"
  chmod +x "$pkg/scripts/$l/compile.sh"
  echo "  scripts/$l/compile.sh instalado"
  n=$((n+1))
done
(( n > 0 )) || { echo "install-fn: nenhuma linguagem instalada" >&2; exit 1; }

cat <<'DICAS'
próximos passos:
  1. edite as zonas EDIT-ME de cada scripts/<lang>/compile.sh (protótipo, leitura, chamada)
     — MESMO nome de função em todas as linguagens liberadas;
  2. termine TODO tests/input/* com a linha da SENTINELA: 424242
     (é ela que pega função que consome a entrada — vira SENTINELA-VIOLADA => WA);
  3. sols/good/ recebe SÓ a função (sem main); uma good POR linguagem liberada;
  4. restrinja `languages` do problema às linguagens COM driver (senão trocar de
     linguagem burla o esquema);
  5. mexer em scripts/ muda o tl-checksum => o Painel vai pedir recalibração (correto).
guia completo: mojtools/docs/submissao-de-funcao.md
DICAS
