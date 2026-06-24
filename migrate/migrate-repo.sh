#!/bin/bash
# migrate-repo.sh — migra UM repo legado (gitolite/sr.ht/gitlab) p/ o Gitea, preservando a
# história, gerando .moj-meta.json por problema (dono/público/coleção) e, opcional, convertendo
# os enunciados p/ Markdown canônico. Idempotente. Não toca no checkout NFS (trabalha num clone).
#
#   uso: migrate-repo.sh <repo> [--write] [--convert] [--push] [--map FILE] [--owner LOGIN]
#     (sem flags) DRY-RUN: só mostra o plano + grava migration-report.tsv
#     --write    gera .moj-meta.json (+ --convert os enunciados) num CLONE temporário
#     --convert  converte tex/org -> md canônico (convert-enunciado.sh; sinaliza o long-tail)
#     --push     cria usuário+repo no Gitea e dá push (história), e registra o diretório
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"           # mojtools/migrate
MOJTOOLS_DIR="$(dirname "$HERE")"                                # mojtools
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${RUNDIR:=/home/ribas/moj/run}"
GITEA_LIB="${GITEA_LIB:-/home/ribas/moj/cdmoj/server/api/v1/lib/gitea.sh}"
[[ -f "$GITEA_LIB" ]] && source "$GITEA_LIB"
[[ -f "$MOJTOOLS_DIR/git-broker.sh" ]] && source "$MOJTOOLS_DIR/git-broker.sh"
: "${EPOCHSECONDS:=$(date +%s)}"

REPO=""; WRITE=0; CONVERT=0; PUSH=0; MAP="$HERE/author-map.tsv"; OWNER_OVR=""
while [[ $# -gt 0 ]]; do case "$1" in
  --write) WRITE=1;; --convert) CONVERT=1;; --push) PUSH=1; WRITE=1;;
  --map) MAP="$2"; shift;; --owner) OWNER_OVR="$2"; shift;;
  -*) echo "flag desconhecida: $1" >&2; exit 2;; *) REPO="$1";; esac; shift; done
[[ -n "$REPO" ]] || { echo "uso: migrate-repo.sh <repo> [--write] [--convert] [--push]" >&2; exit 2; }
LEGACY="$MOJ_PROBLEMS_DIR/$REPO"
[[ -d "$LEGACY" ]] || { echo "repo legado inexistente: $LEGACY" >&2; exit 1; }

map_lookup(){ awk -F'\t' -v k="$1" '$1==k{print $2; exit}' "$MAP" 2>/dev/null; }
OWNER="$OWNER_OVR"
[[ -n "$OWNER" ]] || OWNER="$(map_lookup "@repo:$REPO")"
[[ -n "$OWNER" ]] || OWNER="$(map_lookup "@default")"
[[ -n "$OWNER" ]] || OWNER="curador"

title_of(){ # <pkg> -> título do enunciado (md %, org #+title, tex \section/\title)
  local p="$1" f
  for f in "$p/docs/enunciado.md" "$p/docs/enunciado.org" "$p/docs/enunciado.tex"; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.md)  sed -n 's/^% \+//p' "$f" | head -1; return;;
      *.org) sed -n 's/^#+[Tt][Ii][Tt][Ll][Ee]: \+//p' "$f" | head -1; return;;
      *.tex) sed -n 's/.*\\\(section\|title\)\*\?{\([^}]*\)}.*/\2/p' "$f" | head -1; return;;
    esac
  done
}
is_public(){ ! grep -qE '^[[:space:]]*PUBLIC=no' "$1/conf" 2>/dev/null; }
is_problem(){ [[ -f "$1/author" || -f "$1/conf" || -d "$1/tests" || -d "$1/docs" ]]; }

REPORT="${MIGRATION_REPORT:-migration-report.tsv}"
[[ -f "$REPORT" ]] || printf 'repo\tprob\towner\tpublic\tfmt\taction\tnote\n' > "$REPORT"
say(){ printf '%s\n' "$*" >&2; }
say "== migrate $REPO  ->  Gitea owner=$OWNER  (write=$WRITE convert=$CONVERT push=$PUSH) =="

# diretório de trabalho (clone p/ não tocar no NFS)
WORK=""; PKGROOT="$LEGACY"
if [[ $WRITE -eq 1 ]]; then
  WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
  if [[ -d "$LEGACY/.git" ]]; then git clone -q "$LEGACY" "$WORK/r" || { say "falha ao clonar"; exit 1; }
  else mkdir -p "$WORK/r"; cp -a "$LEGACY/." "$WORK/r/"; ( cd "$WORK/r" && git init -q && git add -A && git -c user.email=moj@local -c user.name=moj commit -qm "import $REPO" ); fi
  PKGROOT="$WORK/r"
fi

n=0; npub=0; nconv=0; nflag=0
set +o noglob
for pdir in "$PKGROOT"/*/; do
  pdir="${pdir%/}"; prob="$(basename "$pdir")"; is_problem "$pdir" || continue
  n=$((n+1))
  pub=true; is_public "$pdir" || pub=false; [[ "$pub" == true ]] && npub=$((npub+1))
  fmt=none; for e in md org tex; do [[ -f "$pdir/docs/enunciado.$e" ]] && { fmt=$e; break; }; done
  action=plan; note=""
  if [[ $WRITE -eq 1 ]]; then
    if [[ $CONVERT -eq 1 && "$fmt" != md && "$fmt" != none ]]; then
      if bash "$MOJTOOLS_DIR/convert-enunciado.sh" "$pdir" --write >/dev/null 2>&1; then nconv=$((nconv+1)); note="converted:$fmt"; fmt=md
      else nflag=$((nflag+1)); note="convert-failed:$fmt(curar)"; fi
    fi
    # .moj-meta.json (dono/gitea/público/coleção/título)
    jq -n --arg o "$OWNER" --arg r "$REPO" --argjson pub "$pub" --arg t "$(title_of "$pdir")" '
      {owner:$o, gitea:{owner:$o, repo:$r}, public:$pub, collections:[$r],
       display_title:$t, migrated_at:'"$EPOCHSECONDS"'}' > "$pdir/.moj-meta.json"
    action=written
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$REPO" "$prob" "$OWNER" "$pub" "$fmt" "$action" "$note" >> "$REPORT"
done
say "  problemas=$n  públicos=$npub  convertidos=$nconv  a-curar=$nflag"

if [[ $WRITE -eq 1 ]]; then
  ( cd "$PKGROOT" && git add -A && git -c user.email=moj@local -c user.name="moj migration" \
      commit -qm "moj: metadados de migração${CONVERT:+ + conversão de enunciados}" >/dev/null 2>&1 ) || say "  (nada novo p/ commitar)"
fi

if [[ $PUSH -eq 1 ]]; then
  command -v gitea_ensure_user >/dev/null || { say "lib/gitea.sh ausente — não dá p/ --push"; exit 1; }
  gitea_ensure_user "$OWNER" "$OWNER" "$OWNER@moj.local" || { say "falha ao criar user $OWNER"; exit 1; }
  gitea_ensure_repo "$OWNER" "$REPO" || { say "falha ao criar repo $OWNER/$REPO"; exit 1; }
  command -v gitea_ensure_webhook >/dev/null && gitea_ensure_webhook "$OWNER" "$REPO" 2>/dev/null || true
  tok="$(gitea_ensure_user_token "$OWNER")"; [[ -n "$tok" ]] || { say "falha no token de $OWNER"; exit 1; }
  url="${GITEA_URL%/}/$OWNER/$REPO.git"; url="${url/http:\/\//http://$OWNER@}"
  br="$(git -C "$PKGROOT" symbolic-ref --short HEAD 2>/dev/null)"; : "${br:=master}"
  ( cd "$PKGROOT" && git remote remove gitea 2>/dev/null; git remote add gitea "$url" )
  if git_broker_run "$OWNER" "$tok" "$PKGROOT" push -f gitea "HEAD:master" >/dev/null 2>&1; then
    say "  push OK -> $OWNER/$REPO (história preservada)"
    # registra o diretório no índice de donos (p/ a UI/CLI)
    REG="$CONTESTSDIR/treino/var/problem-repos.json"; cur="$(cat "$REG" 2>/dev/null)"; [[ -n "$cur" ]] || cur='{}'
    ( umask 077; jq -n --argjson cur "$cur" --arg r "$REPO" --arg o "$OWNER" --argjson now "$EPOCHSECONDS" \
        '$cur + {($r):{owner:$o, collaborators:($cur[$r].collaborators // []), collections:[$r], at:$now, migrated:true}}' ) \
      > "$REG.t" 2>/dev/null && mv -f "$REG.t" "$REG"
  else say "  push FALHOU (Gitea alcançável? token?)"; exit 1; fi
fi
say "relatório: $REPORT"
