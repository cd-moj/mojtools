#!/bin/bash
# gen-problem-owners.sh — índice de DONOS p/ a gestão de problemas (Meus/Compartilhados/
# Públicos/Coleções). Varre os pacotes (autor, .moj-meta.json) + o índice servível do treino
# (var/jsons = conjunto público, com títulos) e escreve, atômico:
#   $CONTESTSDIR/treino/var/problem-owners.json
#     { generated_at, count, problems: [ {id, repo, prob, title, author, author_norm,
#                                          owner, collaborators[], collections[], public, html,
#                                          tl_checksum, public_at, good_langs} ] }
# html = ENUNCIADO COMPILADO E SERVÍVEL (json em var/jsons OU var/jsons-private) — vale também
# p/ problema PRIVADO validado (a pill "sem HTML" do painel deixa de ser sinônimo de privado).
# good_langs = extensões das soluções sols/good/* (= linguagens); a gestão marca "revisar" se alguma
# não tem TL calibrado (solução good que não rodou/passou em nenhum juiz).
# public_at = epoch da 1ª publicação (meta.public_at // seed do backfill); null se privado/desconhecido.
# tl_checksum = checksum do pacote (tl-checksum.sh) SÓ p/ problemas já calibrados (têm
# run/tl/<id>.json); a gestão o compara com o checksum calibrado em run/tl p/ marcar "precisa
# recalibrar". "" = não calibrado (staleness não se aplica) ou ainda não carimbado.
# Fonte da verdade de posse/compart./coleção = .moj-meta.json no pacote + registro de donos.
# O índice é a FONTE ÚNICA: problemas SEM dono (legado pré-migração) são IGNORADOS.
# Sem serviço externo (rápido; leitura de arquivos pequenos do repo git local de cada problema).
set -u
: "${MOJ_PROBLEMS_DIR:=/home/ribas/moj/moj-problems}"
: "${CONTESTSDIR:=/home/ribas/moj/contests}"
: "${RUNDIR:=/home/ribas/moj/run}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # p/ achar tl-checksum.sh (irmão)
JD="$CONTESTSDIR/treino/var/jsons"
JDPRIV="$CONTESTSDIR/treino/var/jsons-private"   # enunciado compilado dos PRIVADOS (gen-problem-json)
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
# cache de tl_checksum p/ NÃO re-hashear pacote sem mudança: id -> {head, sig, cks}.
# Assinatura DUPLA: head (commit do repo) + sig (cksum da METADATA — path/modo/tamanho/mtime —
# dos mesmos caminhos que o tl-checksum.sh cobre). Só o head NÃO basta: mudança FORA do git
# (ex.: normalize-pkg-modes --apply trocando 660->644) muda o hash real sem commit e o cache
# servia checksum velho p/ SEMPRE => "precisa recalibrar" fantasma no painel (13 mdp-ifb-ix,
# 2026-07-17). A sig é só stat (sem ler conteúdo) — o custo O(bytes) segue só quando muda.
# Repo sem git (head vazio) sempre recomputa. Auto-poda: grava só entradas calibradas desta passada.
CKSCACHE="$CONTESTSDIR/treino/var/tl-checksum-cache.json"
# metadata dos caminhos do tl-checksum.sh (conf tests/{input,output,score} sols/good scripts),
# sem ler conteúdo — a lista TEM de acompanhar o tl-checksum.sh (fora dela, mudança no arquivo
# não invalida o cache e o checksum velho é servido p/ sempre)
_statsig(){ ( cd "$1" 2>/dev/null || exit 0
  find conf tests/input tests/output tests/score sols/good scripts -type f -printf '%P\t%m\t%s\t%T@\n' 2>/dev/null \
    | LC_ALL=C sort | cksum | awk '{print $1}' ) }
declare -A CKS_HEAD CKS_SIG CKS_CKS
if [[ -f "$CKSCACHE" ]]; then
  while IFS=$'\t' read -r _cid _chead _csig _ccks; do
    [[ -n "$_cid" ]] && { CKS_HEAD["$_cid"]="$_chead"; CKS_SIG["$_cid"]="$_csig"; CKS_CKS["$_cid"]="$_ccks"; }
  done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.head // "")\t\(.value.sig // "")\t\(.value.cks // "")"' "$CKSCACHE" 2>/dev/null)
fi
newcache="$(mktemp)"
# seed lateral de public_at p/ o histórico (backfill; a migração não gravou a data). meta.public_at
# (do .moj-meta.json, daqui pra frente) tem prioridade; o seed cobre os antigos. Ver server/bin/backfill-public-at.sh.
PUBSEED_F="$CONTESTSDIR/treino/var/public-at-seed.json"
declare -A PUBSEED
if [[ -f "$PUBSEED_F" ]]; then
  while IFS=$'\t' read -r _pid _pat; do [[ -n "$_pid" ]] && PUBSEED["$_pid"]="$_pat"; done \
    < <(jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$PUBSEED_F" 2>/dev/null)
fi
skip_re='^(\.|mojtools$|.*\.(tar|bz2|gz|tgz|zip)$|repositorio-template.*|trab-.*)'
set +o noglob
for repodir in "$MOJ_PROBLEMS_DIR"/*; do
  [[ -d "$repodir" ]] || continue
  repo="$(basename "$repodir")"
  [[ "$repo" =~ $skip_re ]] && continue
  [[ -d "$repodir" ]] || continue          # <org> é só um diretório (não mais um repo git)
  for pdir in "$repodir"/*/; do
    pdir="${pdir%/}"; prob="$(basename "$pdir")"
    # é um problema? tem author|conf|tests|docs
    [[ -f "$pdir/author" || -f "$pdir/conf" || -d "$pdir/tests" || -d "$pdir/docs" ]] || continue
    id="$repo#$prob"
    rhead="$(git -C "$pdir" rev-parse HEAD 2>/dev/null)"   # HEAD do repo do PROBLEMA; assina o cache do checksum
    author="$(head -1 "$pdir/author" 2>/dev/null | tr -d '\t\r')"
    # público hoje = está no índice do treino (HTML buildado + servível)
    pub=0; [[ -n "${PUBSET[$id]:-}" ]] && pub=1
    # html = enunciado COMPILADO e servível (público em var/jsons OU privado em jsons-private) —
    # independente do flag public: privado validado tem html; público recém-marcado sem json não.
    htm=0; [[ -n "${PUBSET[$id]:-}" || -f "$JDPRIV/$id.json" ]] && htm=1
    title="${TITLE[$id]:-}"; [[ -n "$title" ]] || title="$prob"
    owner=""; collabs=""; colls="$repo"; mpat=""   # default: o repo é uma "coleção" (curso)
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
        (if .public==true then "1" elif .public==false then "0" else "" end),
        (.public_at // "")' "$meta" 2>/dev/null)
      owner="${_M[0]:-}"; collabs="${_M[1]:-}"; mcolls="${_M[2]:-}"; mtitle="${_M[3]:-}"; mpub="${_M[4]:-}"; mpat="${_M[5]:-}"
      [[ -n "$mcolls" ]] && colls="$mcolls"
      [[ -n "$mtitle" ]] && title="$mtitle"
      [[ -n "$mpub" ]] && pub="$mpub"
    fi
    # public_at: meta (autoritativo) senão o seed do backfill (só faz sentido p/ público)
    pat="$mpat"; [[ -n "$pat" ]] || pat="${PUBSEED[$id]:-}"; pat="${pat//[^0-9]/}"
    an="$(norm "$author")"
    # checksum do pacote SÓ p/ problemas já calibrados (é onde "precisa recalibrar" faz sentido).
    # Reusa do cache se head E sig batem (nem commit nem mudança fora do git); senão recomputa
    # (lê o conteúdo). Casa com o run/tl/<id>.json (juiz e servidor usam o MESMO tl-checksum.sh).
    cks=""
    if [[ -f "$RUNDIR/tl/$id.json" ]]; then
      sig="$(_statsig "$pdir")"
      if [[ -n "$rhead" && "${CKS_HEAD[$id]:-}" == "$rhead" && -n "$sig" \
            && "${CKS_SIG[$id]:-}" == "$sig" && -n "${CKS_CKS[$id]:-}" ]]; then
        cks="${CKS_CKS[$id]}"
      else
        cks="$(bash "$HERE/tl-checksum.sh" "$pdir" 2>/dev/null)"; cks="${cks//[^0-9a-f]/}"
      fi
      [[ -n "$rhead" ]] && printf '%s\t%s\t%s\t%s\n' "$id" "$rhead" "$sig" "$cks" >> "$newcache"
    fi
    # linguagens das soluções good (extensão = a linguagem que o calibreitor keya). A gestão compara
    # com o TL servido: linguagem good SEM TL = solução good que não calibrou (falhou em todos os hosts).
    gl=""
    [[ -d "$pdir/sols/good" ]] && gl="$(for gf in "$pdir/sols/good"/*; do [[ -f "$gf" ]] && { e="${gf##*.}"; case "$e" in py2|py3) e=py;; esac; [[ "$e" != "$gf" ]] && echo "$e"; }; done | LC_ALL=C sort -u | paste -sd, -)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$repo" "$prob" "${author//$'\t'/ }" "$an" "${title//$'\t'/ }" "$pub" "$owner" "$collabs" "$colls" "$cks" "$pat" "$gl" "$htm" \
      | tr -d '\r' >> "$tsv"
  done
done
# grava o cache de checksums (atômico). Só as entradas desta passada -> some quem deixou de ser
# calibrado. Falha do jq não derruba a geração do índice (cache é best-effort).
jq -Rn '[inputs|split("\t")|select(length>=4)|{key:.[0], value:{head:.[1], sig:.[2], cks:.[3]}}]|from_entries' \
  "$newcache" > "$CKSCACHE.tmp.$$" 2>/dev/null && mv -f "$CKSCACHE.tmp.$$" "$CKSCACHE" || rm -f "$CKSCACHE.tmp.$$"
rm -f "$newcache"

# 3) monta o JSON final numa passada (TSV -> JSON). Aplica o registro de diretórios
#    (problem-repos.json): repos migrados/criados dão dono+colaboradores ao problema mesmo
#    antes do .moj-meta.json ser commitado no repo do problema.
REG="$CONTESTSDIR/treino/var/problem-repos.json"; reg="$(cat "$REG" 2>/dev/null)"; [[ -n "$reg" ]] || reg='{}'
jq -Rn --argjson now "$(date +%s 2>/dev/null || echo 0)" --argjson reg "$reg" '
  [ inputs | split("\t")
    | .[1] as $repo | ($reg[$repo] // {}) as $rr
    | { id:.[0], repo:$repo, prob:.[2], author:.[3], author_norm:.[4], title:.[5],
        public:(.[6]=="1"), html:((.[13] // .[6])=="1"),
        owner:(if (.[7]//"")=="" then ($rr.owner // null) else .[7] end),
        collaborators:(if (.[8]//"")=="" then ($rr.collaborators // []) else (.[8]|split(",")|map(select(length>0))) end),
        collections:((.[9]//"")|split(",")|map(select(length>0))),
        tl_checksum:(.[10] // ""),
        public_at:((.[11] // "")|if .=="" then null else tonumber end),
        good_langs:((.[12] // "")|split(",")|map(select(length>0))) }
    | select(.owner != null) ]
  | { generated_at:$now, count:length, problems:. }' "$tsv" > "$TMP" 2>/dev/null

if jq -e . "$TMP" >/dev/null 2>&1; then
  mv -f "$TMP" "$OUT"
  echo "problem-owners: $(jq -r '.count' "$OUT") problemas -> $OUT"
else
  echo "!! falha ao gerar $OUT" >&2; rm -f "$TMP" "$tsv"; exit 1
fi
rm -f "$tsv"
