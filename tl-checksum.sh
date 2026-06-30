#!/bin/bash
# tl-checksum.sh <pkgdir> — imprime um checksum (16 hex) dos arquivos que AFETAM o
# TIME LIMIT (e a compilação/execução) de um problema: conf + tests/input/* +
# sols/good/* + scripts/* (correção especial: compile/run/compare/prep por linguagem).
# Determinístico (nomes ordenados + conteúdo; p/ scripts inclui o MODO/bit de execução).
# Muda se-e-somente-se o TL pode mudar OU a forma de compilar/rodar/comparar as soluções
# muda — então o juiz usa-o p/ saber quando RE-BAIXAR o pacote e RECALIBRAR (e o MOJ p/
# DESCARTAR o tl antigo). Enunciado, tags e saídas esperadas NÃO entram (não mudam o tempo
# de execução das soluções good). Problemas sem scripts/ ficam com o checksum inalterado.
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
  # scripts de correção especial (compile/run/compare/prep por linguagem): mudam a
  # COMPILAÇÃO/EXECUÇÃO/comparação das soluções — logo podem mudar o TL e EXIGEM que o
  # juiz re-baixe o pacote. Inclui o MODO (bit de execução, ex.: chmod +x do compile.sh).
  if [[ -d "$pkg/scripts" ]]; then
    while IFS= read -r f; do
      printf '=%s mode=%s\n' "${f#"$pkg"/}" "$(stat -c '%a' "$f" 2>/dev/null)"; cat "$f"; printf '\n'
    done < <(find "$pkg/scripts" -type f 2>/dev/null | LC_ALL=C sort)
  fi
} | sha256sum | cut -c1-16
