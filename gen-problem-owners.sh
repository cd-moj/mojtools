#!/bin/bash
# gen-problem-owners.sh — índice de DONOS p/ a gestão de problemas (Meus/Compartilhados/
# Públicos/Coleções). Varre os pacotes (autor, .moj-meta.json) + o índice servível do treino
# (var/jsons = conjunto público, com títulos) e escreve, atômico:
#   $CONTESTSDIR/treino/var/problem-owners.json
#     { generated_at, count, problems: [ {id, repo, prob, title, author, author_norm,
#                                          owner, collaborators[], collections[], public, html} ] }
# Fonte da verdade de posse/compart./coleção = .moj-meta.json no pacote + registro de donos.
# Gitea é a FONTE ÚNICA: problemas SEM dono (legado pré-migração) são IGNORADOS no índice.
# Não chama o Gitea (rápido; leitura de arquivos pequenos do cache de pacotes).
set -u
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
JD="$CONTESTSDIR/treino/var/jsons"
OUT="$CONTESTSDIR/treino/var/problem-owners.json"
TMP="$OUT.tmp.$$"

# normaliza p/ casamento (minúsculas, sem acento, só [a-z0-9 ])
norm(){ printf '%s' "$1" | iconv -f utf-8 -t ascii//TRANSLIT 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9 ' ' ' | tr -s ' '; }

# 1) títulos do conjunto público, numa passada só (id '#' -> title); chaves = problemas em treino
declare -A TITLE PUBSET
if [[ -d "$JD" ]]; then
  while IFS=$'\t' read -r id t; do
    [[ -n "$id" ]] || continue
    TITLE["$id"]="$t"; PUBSET["$id"]=1
  done < <(set +o noglob; jq -rn '
      reduce inputs as $x ({}; . + {((input_filename|sub(".*/";"")|sub("\\.json$";""))): ($x.title // "")})
      | to_entries[] | "\(.key)\t\(.value)"' "$JD"/*.json 2>/dev/null)
fi

# 2) varre os pacotes -> TSV (uma linha por problema)
tsv="$(mktemp)"
skip_re='^(\.|mojtools$|.*\.(tar|bz2|gz|tgz|zip)$|repositorio-template.*|trab-.*)'
set +o noglob
for repodir in "$MOJ_PROBLEMS_DIR"/*; do
  [[ -d "$repodir" ]] || continue
  repo="$(basename "$repodir")"
  [[ "$repo" =~ $skip_re ]] && continue
  [[ -d "$repodir/.git" || -f "$repodir/.git" ]] || [[ -d "$repodir" ]] || continue
  for pdir in "$repodir"/*/; do
    pdir="${pdir%/}"; prob="$(basename "$pdir")"
    # é um problema? tem author|conf|tests|docs
    [[ -f "$pdir/author" || -f "$pdir/conf" || -d "$pdir/tests" || -d "$pdir/docs" ]] || continue
    id="$repo#$prob"
    author="$(head -1 "$pdir/author" 2>/dev/null | tr -d '\t\r')"
    # público hoje = está no índice do treino (HTML buildado + servível)
    pub=0; [[ -n "${PUBSET[$id]:-}" ]] && pub=1
    title="${TITLE[$id]:-}"; [[ -n "$title" ]] || title="$prob"
    owner=""; collabs=""; colls="$repo"   # default: o repo é uma "coleção" (curso)
    meta="$pdir/.moj-meta.json"
    if [[ -f "$meta" ]]; then
      # uma LINHA por campo + mapfile: preserva os campos VAZIOS por POSIÇÃO. (read/@tsv NÃO serve:
      # tab é caractere de espaço no IFS, então `read` colapsa campos vazios — o public(0/1) ou uma
      # palavra do título caía em `collections`, criando coleções "estragadas" tipo "0"/"1".)
      mapfile -t _M < <(jq -r '
        (.owner // .gitea.owner // ""),
        ((.collaborators // []) | join(",")),
        ((.collections // []) | join(",")),
        (.display_title // ""),
        (if .public==true then "1" elif .public==false then "0" else "" end)' "$meta" 2>/dev/null)
      owner="${_M[0]:-}"; collabs="${_M[1]:-}"; mcolls="${_M[2]:-}"; mtitle="${_M[3]:-}"; mpub="${_M[4]:-}"
      [[ -n "$mcolls" ]] && colls="$mcolls"
      [[ -n "$mtitle" ]] && title="$mtitle"
      [[ -n "$mpub" ]] && pub="$mpub"
    fi
    an="$(norm "$author")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$repo" "$prob" "${author//$'\t'/ }" "$an" "${title//$'\t'/ }" "$pub" "$owner" "$collabs" "$colls" \
      | tr -d '\r' >> "$tsv"
  done
done

# 3) monta o JSON final numa passada (TSV -> JSON). Aplica o registro de diretórios
#    (problem-repos.json): repos migrados/criados dão dono+colaboradores ao problema mesmo
#    antes do .moj-meta.json chegar ao NFS.
REG="$CONTESTSDIR/treino/var/problem-repos.json"; reg="$(cat "$REG" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
jq -Rn --argjson now "$(date +%s 2>/dev/null || echo 0)" --argjson reg "$reg" '
  [ inputs | split("\t")
    | .[1] as $repo | ($reg[$repo] // {}) as $rr
    | { id:.[0], repo:$repo, prob:.[2], author:.[3], author_norm:.[4], title:.[5],
        public:(.[6]=="1"), html:(.[6]=="1"),
        owner:(if (.[7]//"")=="" then ($rr.owner // null) else .[7] end),
        collaborators:(if (.[8]//"")=="" then ($rr.collaborators // []) else (.[8]|split(",")|map(select(length>0))) end),
        collections:((.[9]//"")|split(",")|map(select(length>0))) }
    | select(.owner != null) ]
  | { generated_at:$now, count:length, problems:. }' "$tsv" > "$TMP" 2>/dev/null

if jq -e . "$TMP" >/dev/null 2>&1; then
  mv -f "$TMP" "$OUT"
  echo "problem-owners: $(jq -r '.count' "$OUT") problemas -> $OUT"
else
  echo "!! falha ao gerar $OUT" >&2; rm -f "$TMP" "$tsv"; exit 1
fi
rm -f "$tsv"
