#!/bin/bash
# consolidate-remotes.sh — para um repo legado espalhado (sr.ht/gitlab/gitolite), adiciona os
# remotes alternativos e faz fetch, p/ reunir toda a história num só checkout ANTES de migrar.
#   uso: consolidate-remotes.sh <repo-dir> <nome=url> [<nome=url> ...]
#   ex.: consolidate-remotes.sh moj-problems/eda2-problems \
#          srht=git@git.sr.ht:~bcribas/eda2-problems gitlab=git@gitlab.com:bcribas/eda2.git
set -u
DIR="${1:?uso: consolidate-remotes.sh <repo-dir> <nome=url> ...}"; shift
[[ -d "$DIR/.git" ]] || { echo "não é repo git: $DIR" >&2; exit 1; }
for spec in "$@"; do
  name="${spec%%=*}"; url="${spec#*=}"
  [[ -n "$name" && -n "$url" && "$name" != "$url" ]] || { echo "spec inválido: $spec (use nome=url)" >&2; continue; }
  git -C "$DIR" remote remove "$name" 2>/dev/null
  git -C "$DIR" remote add "$name" "$url"
  printf 'fetch %s <- %s : ' "$name" "$url"
  git -C "$DIR" fetch -q "$name" && echo ok || echo "FALHOU (verifique acesso)"
done
echo "pronto. revise com 'git -C $DIR log --all --oneline' antes de 'migrate-repo.sh'."
