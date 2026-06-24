# git-broker.sh — git ESCONDIDO (server-side). A web/CLI nunca tocam git nem chaves: o
# servidor commita como o autor real e dá push no Gitea via HTTPS usando um token efêmero
# entregue por GIT_ASKPASS (env do filho), NUNCA no .git/config nem no argv. Sourced por
# handlers que já têm common.conf + lib/gitea.sh carregados.
#
# Requer no ambiente: GITEA_URL, GITEA_USER_TOKENS_DIR (de common.conf). Resolve o token do
# autor via cache 600 e, se a lib estiver presente, via gitea_ensure_user_token (lazy).
: "${GITEA_URL:=http://localhost:3939}"
: "${GITEA_USER_TOKENS_DIR:=${RUNDIR:-/home/ribas/moj/run}/secrets/gitea-user-tokens}"

# _gb_token <login> -> ecoa o token HTTPS do autor (provisiona se a lib gitea estiver carregada)
_gb_token(){
  local login="$1"
  [[ -n "${MOJ_GIT_TOKEN:-}" ]] && { printf '%s' "$MOJ_GIT_TOKEN"; return 0; }
  local f="$GITEA_USER_TOKENS_DIR/$login"
  [[ -s "$f" ]] && { cat "$f"; return 0; }
  declare -F gitea_ensure_user_token >/dev/null && gitea_ensure_user_token "$login"
}

# _gb_host_url -> host:porta sem esquema (p/ montar URL com usuário embutido)
_gb_repo_url(){ printf '%s/%s/%s.git' "${GITEA_URL%/}" "$1" "$2"; }

# git_broker_run <login> <token> <dir> <git-args...> — roda 1 comando git autenticado.
# Token só existe no env do askpass (GIT_ASKPASS), some ao retornar. Sem prompt interativo.
git_broker_run(){
  local login="$1" token="$2" dir="$3"; shift 3
  local ap; ap="$(mktemp)"; printf '#!/bin/sh\nprintf %%s "$MOJ_GIT_TOKEN"\n' > "$ap"; chmod 700 "$ap"
  MOJ_GIT_TOKEN="$token" GIT_ASKPASS="$ap" GIT_TERMINAL_PROMPT=0 \
    git -C "$dir" -c credential.helper= "$@"
  local rc=$?; rm -f "$ap"; return $rc
}

# git_broker_clone <login> <owner> <repo> <destdir> [--depth N] — clone autenticado (sem segredo persistido)
git_broker_clone(){
  local login="$1" owner="$2" repo="$3" dest="$4"; shift 4
  local token; token="$(_gb_token "$login")" || return 2
  [[ -n "$token" ]] || return 2
  local url; url="$(_gb_repo_url "$owner" "$repo")"
  url="${url/http:\/\//http://$login@}"; url="${url/https:\/\//https://$login@}"
  local ap; ap="$(mktemp)"; printf '#!/bin/sh\nprintf %%s "$MOJ_GIT_TOKEN"\n' > "$ap"; chmod 700 "$ap"
  MOJ_GIT_TOKEN="$token" GIT_ASKPASS="$ap" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= clone -q "$@" "$url" "$dest"
  local rc=$?; rm -f "$ap"; return $rc
}

# git_broker_commit_push <login> <owner> <repo> <worktree> <msg> [email] — commita TODO o
# worktree como o autor (--author) e dá push p/ o branch atual. Idempotente: nada a commitar => push só.
git_broker_commit_push(){
  local login="$1" owner="$2" repo="$3" wt="$4" msg="$5" email="${6:-$login@moj.local}"
  [[ -d "$wt/.git" ]] || return 2
  local token; token="$(_gb_token "$login")" || return 2; [[ -n "$token" ]] || return 2
  git -C "$wt" add -A
  if ! git -C "$wt" diff --cached --quiet; then
    git -C "$wt" -c "user.name=$login" -c "user.email=$email" \
      commit -q --author="$login <$email>" -m "$msg" || return 3
  fi
  local branch; branch="$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)"; : "${branch:=master}"
  git_broker_run "$login" "$token" "$wt" push -q origin "HEAD:$branch" || return 4
  git -C "$wt" rev-parse HEAD   # ecoa o SHA novo (caller usa p/ relatar)
}

# git_broker_open <login> <owner> <repo> — clona shallow num temp e ecoa o <tmpdir>
# (worktree = <tmpdir>/wt). O chamador escreve em <tmpdir>/wt, chama git_broker_commit_push
# e remove o <tmpdir> ao final. Permite editar vários arquivos e commitar num só commit.
git_broker_open(){
  local login="$1" owner="$2" repo="$3" tmp; tmp="$(mktemp -d)"
  if git_broker_clone "$login" "$owner" "$repo" "$tmp/wt" --depth 1; then printf '%s' "$tmp"
  else rm -rf "$tmp"; return 1; fi
}

# git_broker_sync_push <login> <owner> <repo> <srcdir> <subpath> <msg> — caso autoria web:
# clona o repo num temp, espelha srcdir -> <subpath>/, commita como o autor e pusha. Ecoa o
# SHA novo no stdout. Limpa o temp sempre. <subpath> vazio => raiz do repo.
git_broker_sync_push(){
  local login="$1" owner="$2" repo="$3" src="$4" sub="$5" msg="$6"
  [[ -d "$src" ]] || return 2
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  git_broker_clone "$login" "$owner" "$repo" "$tmp/wt" --depth 1 || return 4
  local target="$tmp/wt${sub:+/$sub}"
  mkdir -p "$target"
  # espelha o pacote (remove o que sumiu), preservando o .git do worktree
  rsync -a --delete --exclude='.git' "$src/" "$target/" 2>/dev/null \
    || { rm -rf "$target"; mkdir -p "$target"; cp -a "$src/." "$target/"; }
  git_broker_commit_push "$login" "$owner" "$repo" "$tmp/wt" "$msg" || return 5
  git -C "$tmp/wt" rev-parse HEAD
}
