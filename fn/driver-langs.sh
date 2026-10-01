#!/bin/bash
# driver-langs.sh <pkgdir> — lista (uma por linha, ids canônicos, sem repetição) as linguagens cujo
# scripts/<lang>/compile.sh ESCREVE UM `main` NUM HEREDOC: o driver de submissão de função (o aluno
# envia só a função; o main do autor vem inline no compile.sh — docs/submissao-de-funcao.md).
#
# É uma HEURÍSTICA e NÃO é o sinal de "problema de função": o sinal é a linha FUNCTION_LANGS do conf,
# declarada pelo autor (cdmoj/docs/PACOTE.md). O slot COMPILE também serve p/ ban de função e p/
# OpenMP/MPI, em que o aluno escreve o programa inteiro — e um driver pode ser escrito de outro jeito
# (um arquivo copiado em vez de heredoc). Usos: o aviso do validate-problem.sh ("driver não
# declarado") e a migração cdmoj/server/bin/function-langs-migrate.sh, que PROPÕE a linha.
# Medido no acervo em 30/09/2026: 201 compile.sh em 77 pacotes — 156 com main em heredoc, 45 sem
# (ban/programa completo), nenhum ambíguo.
set -u
pkg="${1:?uso: driver-langs.sh <pkgdir>}"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$HERE/../lang-canon.sh"
[[ -d "$pkg/scripts" ]] || exit 0
find "$pkg/scripts" -mindepth 2 -maxdepth 2 -name compile.sh -type f 2>/dev/null | sort | while IFS= read -r f; do
  # linha de main DENTRO de um heredoc (<<EOF, <<'EOF', <<-"EOF"…) — fora dele é o próprio script
  if awk '
      h == "" && match($0, /<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*/) {
        t = substr($0, RSTART, RLENGTH); sub(/^<<-?[[:space:]]*["'"'"']?/, "", t); h = t; next }
      h != "" { s = $0; sub(/^[[:space:]]+/, "", s); if (s == h) { h = ""; next }
                if ($0 ~ /main[[:space:]]*\(|def main|fun main|static void main|fn main|__name__/) { found = 1 } }
      END { exit(found ? 0 : 1) }' "$f"; then
    lang_canon "$(basename "$(dirname "$f")")"; printf '\n'
  fi
done | awk 'NF && !seen[$0]++'
