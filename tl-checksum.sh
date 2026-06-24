#!/bin/bash
# tl-checksum.sh <pkgdir> — imprime um checksum (16 hex) dos arquivos que AFETAM o
# TIME LIMIT de um problema: conf + tests/input/* + sols/good/*. Determinístico
# (nomes ordenados + conteúdo). Muda se-e-somente-se o TL pode mudar — então o juiz
# usa-o p/ saber quando RECALIBRAR (e o MOJ p/ DESCARTAR o tl antigo). Enunciado, tags
# e saídas esperadas NÃO entram (não mudam o tempo de execução das soluções good).
#   uso: tl-checksum.sh <pkgdir>     ->  ex.: 3f9a1c0b8e7d6a5b
set -u
pkg="${1:?uso: tl-checksum.sh <pkgdir>}"
[[ -d "$pkg" ]] || { echo "tl-checksum: pacote inexistente: $pkg" >&2; exit 1; }
{
  # conf: calibrafactor/ULIMITS/CALIBRATIONTL/ALLOWPARALLELTEST/etc. mudam o TL
  if [[ -f "$pkg/conf" ]]; then printf '=conf\n'; cat "$pkg/conf"; printf '\n'; fi
  # entradas dos testes + soluções "good" (o que é efetivamente cronometrado)
  for d in tests/input sols/good; do
    [[ -d "$pkg/$d" ]] || continue
    while IFS= read -r f; do
      printf '=%s\n' "${f#"$pkg"/}"; cat "$f"; printf '\n'
    done < <(find "$pkg/$d" -type f 2>/dev/null | LC_ALL=C sort)
  done
} | sha256sum | cut -c1-16
