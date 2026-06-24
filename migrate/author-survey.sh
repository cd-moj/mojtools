#!/bin/bash
# author-survey.sh — levanta os autores (texto livre) dos pacotes p/ semear o author-map.tsv
# curado. Saída: authors.tsv  (autor \t n \t exemplo \t sugestao_login).  Best-effort.
#   uso: author-survey.sh [saida.tsv]
set -u
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
OUT="${1:-authors.tsv}"
skip_re='^(\.|mojtools$|.*\.(tar|bz2|gz|tgz|zip)$|repositorio-template.*|trab-.*)'

# sugere um login a partir do nome livre (tira parênteses; junta 1º+2º token; minúsculas/sem acento)
suggest(){ printf '%s' "$1" | sed 's/(.*//' | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null \
  | tr 'A-Z' 'a-z' | tr -c 'a-z ' ' ' | awk '{print ($2!=""?$1$2:$1)}'; }

declare -A CNT EX
set +o noglob
for repodir in "$MOJ_PROBLEMS_DIR"/*; do
  [[ -d "$repodir" ]] || continue; repo="$(basename "$repodir")"; [[ "$repo" =~ $skip_re ]] && continue
  for pdir in "$repodir"/*/; do
    pdir="${pdir%/}"; [[ -f "$pdir/author" ]] || continue
    a="$(head -1 "$pdir/author" | tr -d '\t\r')"; [[ -n "$a" ]] || a="(vazio)"
    CNT["$a"]=$(( ${CNT["$a"]:-0} + 1 ))
    [[ -z "${EX["$a"]:-}" ]] && EX["$a"]="$repo#$(basename "$pdir")"
  done
done
{ printf 'autor\tn\texemplo\tsugestao_login\n'
  for a in "${!CNT[@]}"; do printf '%s\t%s\t%s\t%s\n' "$a" "${CNT[$a]}" "${EX[$a]}" "$(suggest "$a")"; done \
    | sort -t$'\t' -k2 -rn
} > "$OUT"
echo "autores distintos: ${#CNT[@]} -> $OUT"
