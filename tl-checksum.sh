#!/bin/bash
# tl-checksum.sh <pkgdir> — imprime um checksum (16 hex) dos arquivos que AFETAM o
# JULGAMENTO de um problema: conf + tests/{input,output,score} + sols/good/* + scripts/*
# (correção especial: compile/run/compare/prep por linguagem).
# Determinístico (nomes ordenados + conteúdo; p/ scripts inclui o MODO/bit de execução).
# Muda se-e-somente-se o TL pode mudar OU o VEREDICTO pode mudar (saída esperada, grupos
# do score, forma de compilar/rodar/comparar) — o juiz usa-o p/ saber quando RE-BAIXAR o
# pacote (e RECALIBRAR), e o MOJ p/ DESCARTAR o tl antigo. tests/output e tests/score não
# mudam o TEMPO das good, mas mudam o veredicto — e o cache do juiz é invalidado por ESTE
# checksum: fora dele, um score/saída corrigido nunca chegava ao juiz (caso obi2026f1pm_aula:
# juiz julgando com tests/score de uma iteração anterior p/ sempre). Enunciado e tags NÃO
# entram. Mudou a cobertura? re-stampar os checksums guardados (run/tl/*.json) em vez de
# recalibrar tudo — o pacote não mudou, só a função de hash.
#   uso: tl-checksum.sh <pkgdir>     ->  ex.: 3f9a1c0b8e7d6a5b
set -u
pkg="${1:?uso: tl-checksum.sh <pkgdir>}"
[[ -d "$pkg" ]] || { echo "tl-checksum: pacote inexistente: $pkg" >&2; exit 1; }
{
  # conf: calibrafactor/ULIMITS/CALIBRATIONTL/ALLOWPARALLELTEST/etc. mudam o TL
  if [[ -f "$pkg/conf" ]]; then printf '=conf\n'; cat "$pkg/conf"; printf '\n'; fi
  # testes (entrada + saída esperada + grupos do score) + soluções "good"
  for d in tests/input tests/output tests/score sols/good; do
    if [[ -f "$pkg/$d" ]]; then   # tests/score é ARQUIVO
      printf '=%s\n' "$d"; cat "$pkg/$d"; printf '\n'; continue
    fi
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
