#!/bin/bash
#This file is part of CD-MOJ. GPLv3+. See <http://www.gnu.org/licenses/>.

# validate-problem.sh — PORTÃO de qualidade de um pacote de problema. Gera um
# relatório em $RUNDIR/validation/<id>.json e, se passar, gera o índice do treino
# (chama gen-problem-json.sh). "Só sobe/publica o que funciona."
#
#   uso:  validate-problem.sh <pkgdir> [<id>]
#   retorna 0 se passou (e indexou), !=0 se reprovou.
#
# Checagens (hard, salvo indicado):
#   has_author        — existe ./author (o Makefile exige p/ descobrir o problema)
#   has_statement     — existe docs/enunciado.{md,org,tex}
#   html_builds       — o render-statement.sh renderiza o enunciado PT
#   html_builds_<lang>, secao_entrada_<lang>, secao_saida_<lang> — idem p/ cada tradução
#                       docs/enunciado.<lang>.md presente (statement-langs.sh); nota de exemplo sem
#                       tradução é aviso soft `nota-sem-traducao(<sample>,<lang>)` (cai na PT)
#   examples_present  — >=1 exemplo tests/input/sample* com a saída, OU `SAMPLE=no` no conf (o
#                       problema declarou que não tem exemplos: função, interativo, linguagem
#                       própria… — o exemplo vai no texto). Teste oculto NUNCA conta como exemplo.
#   tests_paired      — todo input tem output e vice-versa
#   score_file_sane   — (se tests/score existe) toda linha é '<globs> - N pontos' (ou "#"),
#                       todo teste casa um grupo e todo grupo de peso>0 casa >=1 teste
#   has_good_sol      — >=1 solução em sols/good/
#   good_sol_accepts  — (se VALIDATE_RUN_SOLS=1 e há bwrap) cada sols/good é Accepted
#   scripts_exec      — todo scripts/**/*.sh tem +x (o juiz executa direto; sem o bit é UE)
#   checker_src       — (se compare.sh é o checker testlib) existe scripts/checker.cpp
set -u

PKG="${1:?uso: validate-problem.sh <pkgdir> [id]}"
PKG="$(cd "$PKG" 2>/dev/null && pwd)" || { echo "validate: pkg '$1' inexistente" >&2; exit 1; }
REPODIR="$(dirname "$PKG")"; PROB="$(basename "$PKG")"; REPO="$(basename "$REPODIR")"
ID="${2:-$REPO#$PROB}"
SELF="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SELF/statement-langs.sh"

: "${RUNDIR:=/home/ribas/moj/run}"
: "${VALDIR:=$RUNDIR/validation}"
: "${VALIDATE_RUN_SOLS:=1}"            # 0 = pula a execução das good (útil em dev sem sandbox)
HOSTNAME="${HOSTNAME:-$(hostname)}"
mkdir -p "$VALDIR" 2>/dev/null

declare -a CK
add(){ # add <name> <ok 0|1> [detail]
  CK+=("$(jq -cn --arg n "$1" --argjson ok "$([[ "$2" == 1 ]] && echo true || echo false)" \
        --arg d "${3:-}" '{name:$n, ok:$ok, detail:$d}')"); }

# --- has_author ---
[[ -f "$PKG/author" ]] && add has_author 1 || add has_author 0 "falta o arquivo 'author'"

# --- has_statement (PT = docs/enunciado.{md,org,tex}; a descoberta é a do statement-langs.sh) ---
enunf="$(stmt_file "$PKG" pt)" || enunf=""
[[ "$enunf" == "$PKG/docs/"* ]] || enunf=""
efmt=md; [[ -n "$enunf" ]] && efmt="$(stmt_fmt "$enunf")"
[[ -n "$enunf" ]] && add has_statement 1 "enunciado.$efmt" || add has_statement 0 "sem docs/enunciado.{md,org,tex}"

# --- html_builds (MESMO renderizador do "Pré-visualizar": render-statement.sh — pandoc
#     standalone, sem o Makefile/scaffolding do repo; funciona p/ legados e problemas atuais) ---
html_built=false; render_leak=""
if [[ -n "$enunf" ]]; then
  rendered="$(bash "$SELF/render-statement.sh" "$enunf" "$efmt" "" "" pt 2>/dev/null)"
  if printf '%s' "$rendered" | grep -qi '</body>'; then
    html_built=true; add html_builds 1
    # vaza LaTeX de PROSA no HTML? (informativo — math via mathml é OK)
    render_leak="$(printf '%s' "$rendered" | grep -oE '\\(textbf|textit|subsection|section|arquivoProblema|begin\{(itemize|enumerate|center)\}|emph|underline)' | sort -u | tr '\n' ' ')"
  else
    add html_builds 0 "pandoc não renderizou o enunciado ($efmt)"
  fi
else
  add html_builds 0 "sem docs/enunciado.{md,org,tex}"
fi

# --- seções esperadas no enunciado (OBRIGATÓRIAS p/ liberar): ## Entrada e ## Saída ---
ebody=""; [[ -n "$enunf" ]] && ebody="$(cat "$enunf" 2>/dev/null)"
if grep -qiE '^[[:space:]]*#{1,3}[[:space:]]*(entrada|input)' <<<"$ebody"; then add secao_entrada 1; else add secao_entrada 0 "falta a seção '## Entrada'"; fi
if grep -qiE '^[[:space:]]*#{1,3}[[:space:]]*(saída|saida|salida|output)' <<<"$ebody"; then add secao_saida 1; else add secao_saida 0 "falta a seção '## Saída'"; fi
# --- traduções (docs/enunciado.<lang>.md): cada uma renderiza e tem as seções (HARD, como a PT) ---
for _tl in $(stmt_langs_of "$PKG"); do
  [[ "$_tl" == pt ]] && continue
  _tf="$(stmt_file "$PKG" "$_tl")"
  if bash "$SELF/render-statement.sh" "$_tf" md "" "" "$_tl" 2>/dev/null | grep -qi '</body>'; then add "html_builds_$_tl" 1 "enunciado.$_tl.md"
  else add "html_builds_$_tl" 0 "pandoc não renderizou docs/enunciado.$_tl.md"; fi
  _tb="$(cat "$_tf" 2>/dev/null)"
  if grep -qiE '^[[:space:]]*#{1,3}[[:space:]]*(entrada|input)' <<<"$_tb"; then add "secao_entrada_$_tl" 1; else add "secao_entrada_$_tl" 0 "falta a seção de entrada (## Input / ## Entrada) em enunciado.$_tl.md"; fi
  if grep -qiE '^[[:space:]]*#{1,3}[[:space:]]*(saída|saida|salida|output)' <<<"$_tb"; then add "secao_saida_$_tl" 1; else add "secao_saida_$_tl" 0 "falta a seção de saída (## Output / ## Salida) em enunciado.$_tl.md"; fi
  # nota PT sem tradução: o aluno que lê em $_tl vê a explicação em PT (soft)
  for _nf in "$PKG/docs/notes"/*.md; do
    [[ -e "$_nf" ]] || continue; _nb="$(basename "$_nf" .md)"
    { [[ "$_nb" == *.* ]] && stmt_lang_ok "${_nb##*.}"; } && continue   # já é uma nota traduzida (sample.1.md não é)
    [[ -f "$PKG/docs/notes/$_nb.$_tl.md" ]] || render_leak="${render_leak}nota-sem-traducao($_nb,$_tl) "
  done
done
# --- aviso SOFT (não bloqueia): exemplo embutido no texto -> deve vir da lista de exemplos ---
# (com SAMPLE=no o texto É o lugar do exemplo: sem aviso)
# (chaves: sem elas o `||` escapava da condição e um bloco de código avisava mesmo com SAMPLE=no)
if ! stmt_no_samples "$PKG" && { grep -qiE '^[[:space:]]*#{1,3}[[:space:]]*(exemplos?|examples?|sample)' <<<"$ebody" || grep -qE '^[[:space:]]*```' <<<"$ebody"; }; then
  render_leak="${render_leak}exemplo-no-texto? "
fi
# --- aviso SOFT: notas de exemplo desemparelhadas (nota truncada/deslocada passava MUDA) ---
# formato novo docs/notes/<sample>.md: nota sem sample correspondente = sobra;
# legado sample-notes.json: contagem de notas != contagem de samples.
if [[ -d "$PKG/docs/notes" ]]; then
  for _nf in "$PKG/docs/notes"/*.md; do
    [[ -e "$_nf" ]] || continue
    _nb="$(basename "$_nf" .md)"
    # sufixo de idioma (sample1.en.md): o sample é o que vem antes do último ponto
    _ns="$_nb"; if [[ "$_nb" == *.* ]] && stmt_lang_ok "${_nb##*.}"; then _ns="${_nb%.*}"; fi
    [[ -f "$PKG/tests/input/$_ns" ]] || render_leak="${render_leak}nota-sem-sample($_nb) "
  done
elif [[ -f "$PKG/docs/sample-notes.json" ]]; then
  _nn="$(jq 'length' "$PKG/docs/sample-notes.json" 2>/dev/null)"
  _ns="$(find "$PKG/tests/input" -maxdepth 1 -name 'sample*' 2>/dev/null | wc -l)"
  [[ "$_nn" =~ ^[0-9]+$ ]] && (( _nn != _ns )) && render_leak="${render_leak}notas($_nn)!=samples($_ns) "
fi
# --- aviso SOFT: checker BINÁRIO commitado como compare.sh (padrão antigo/deprecado) ---
# normalize p/ fonte + bridge: scripts/checker.cpp via mojtools/testlib/install-checker.sh
compare_elf=false
if [[ -f "$PKG/scripts/compare.sh" ]] && file -b "$PKG/scripts/compare.sh" 2>/dev/null | grep -q ELF; then
  compare_elf=true
  render_leak="${render_leak}compare.sh-binário(use-testlib/install-checker.sh) "
fi

# --- scripts_exec (HARD): o bit +x da correção especial é LOAD-BEARING e nada mais o checava.
#     O compare.sh é EXECUTADO pelo juiz (no host, FORA da jaula), o <lang>/prep.sh é testado
#     com -x antes do source, e <lang>/{compile,run}.sh são montados na JAULA e executados
#     DIRETO. Sem o bit: "Permission denied" (exit 126) => UE em TODO teste — e o tl-checksum
#     ainda passa a divergir do servidor (o modo entra no hash). ---
noexec=""
if [[ -d "$PKG/scripts" ]]; then
  while IFS= read -r f; do [[ -x "$f" ]] || noexec+="${f#"$PKG/"} "; done \
    < <(find "$PKG/scripts" -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort)
fi
[[ -z "$noexec" ]] && add scripts_exec 1 \
  || add scripts_exec 0 "sem +x (o juiz executa o script direto => UE em todo teste): $noexec"

# --- checker_src (HARD): compare.sh é o bridge/stub do testlib => o FONTE tem de vir junto.
#     (O bridge compila scripts/checker.cpp no juiz, sob demanda; sem o fonte, todo teste é UE.) ---
if [[ -f "$PKG/scripts/compare.sh" && "$compare_elf" == false ]] \
   && grep -qE 'checker-bridge|checker\.cpp' "$PKG/scripts/compare.sh" 2>/dev/null; then
  [[ -f "$PKG/scripts/checker.cpp" ]] && add checker_src 1 "scripts/checker.cpp" \
    || add checker_src 0 "compare.sh é o checker testlib, mas falta scripts/checker.cpp"
fi

# --- aviso SOFT: validador de ENTRADA (scripts/validator.cpp, testlib/validator-run.sh) sem
#     registerValidation — a testlib não entra no modo validador e o validador não confere nada.
#     Quem RODA o validador é a calibração (no juiz); aqui só a forma. ---
if [[ -f "$PKG/scripts/validator.cpp" ]] && ! grep -q 'registerValidation' "$PKG/scripts/validator.cpp" 2>/dev/null; then
  render_leak="${render_leak}validador-sem-registerValidation "
fi

# --- examples / tests pairing ---
ninput=0; npair=0; unpaired=""
if [[ -d "$PKG/tests/input" ]]; then
  for f in "$PKG/tests/input/"*; do
    [[ -e "$f" ]] || continue; ((ninput++)); b="$(basename "$f")"
    if [[ -f "$PKG/tests/output/$b" ]]; then ((npair++)); else unpaired+="$b "; fi
  done
fi
# outputs sem input
if [[ -d "$PKG/tests/output" ]]; then
  for f in "$PKG/tests/output/"*; do [[ -e "$f" ]] || continue; b="$(basename "$f")"
    [[ -f "$PKG/tests/input/$b" ]] || unpaired+="out:$b "; done
fi
nsample=0
if [[ -d "$PKG/tests/input" ]]; then
  for f in "$PKG/tests/input/"sample*; do [[ -e "$f" && -f "$PKG/tests/output/$(basename "$f")" ]] && ((nsample++)); done
fi
if stmt_no_samples "$PKG"; then
  add examples_present 1 "sem exemplos (SAMPLE=no no conf)"
  (( nsample > 0 )) && render_leak="${render_leak}sample-oculto-por-SAMPLE=no($nsample) "
elif (( nsample >= 1 )); then add examples_present 1 "$nsample exemplo(s)"
else add examples_present 0 "sem exemplos: crie tests/input/sample1 e tests/output/sample1, ou declare SAMPLE=no no conf se o problema não tem exemplo (função, interativo…)"; fi
[[ -z "$unpaired" ]] && add tests_paired 1 "$npair par(es)" || add tests_paired 0 "sem par: $unpaired"

# --- score_file_sane (HARD): tests/score que não casa os testes vira grupo-fantasma "-1"/
#     NOGROUP no juiz e derruba o veredicto MESMO com todos os testes AC (caso
#     obi2026f1pm_aula). Espelha a semântica do score-summary.sh: "#" = comentário; linha
#     de grupo = '<glob>[, <glob>…] - <N> pontos'; teste casa grupo por
#     prefixo-sem-dígitos-finais, nome exato OU glob real. ---
if [[ -f "$PKG/tests/score" ]]; then
  shopt -s extglob
  sc_badline=""; sc_pats=(); sc_wts=()
  while IFS='-' read -r _g _s || [[ -n "$_g" ]]; do
    [[ "$_g" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${_g//[[:space:]]/}" ]] && continue
    if [[ -z "${_s//[^0-9]/}" ]]; then sc_badline+="'$_g' "; continue; fi
    _pl=""
    set -f; for _p in $_g; do _p="${_p%,}"; _pl+="${_pl:+ }$_p"; done; set +f
    sc_pats+=("$_pl"); sc_wts+=("${_s//[^0-9]/}")
  done < "$PKG/tests/score"
  declare -A sc_hit=()
  sc_nogrp=""
  if [[ -d "$PKG/tests/input" ]]; then
    for f in "$PKG/tests/input/"*; do
      [[ -e "$f" ]] || continue; b="${f##*/}"; gn="${b%%+([0-9])}"
      hit=""
      for _gi in "${!sc_pats[@]}"; do
        set -f
        for _p in ${sc_pats[$_gi]}; do
          pn="${_p%\**}"
          if [[ "$b" == "$pn" || "$gn" == "$pn" || "$b" == $_p ]]; then hit="$_gi"; break 2; fi
        done
        set +f
      done
      set +f
      if [[ -n "$hit" ]]; then sc_hit[$hit]=1; else sc_nogrp+="$b "; fi
    done
  fi
  sc_empty=""
  for _gi in "${!sc_wts[@]}"; do
    (( ${sc_wts[$_gi]} > 0 )) && [[ -z "${sc_hit[$_gi]:-}" ]] && sc_empty+="'${sc_pats[$_gi]}' "
  done
  sc_det=""
  [[ -n "$sc_badline" ]] && sc_det+="linha sem ' - N pontos' (vira grupo-fantasma): $sc_badline; "
  [[ -n "$sc_nogrp"   ]] && sc_det+="teste sem grupo (zera a submissão): $sc_nogrp; "
  [[ -n "$sc_empty"   ]] && sc_det+="grupo de peso>0 sem nenhum teste: $sc_empty"
  [[ -z "$sc_det" ]] && add score_file_sane 1 "${#sc_wts[@]} grupo(s)" \
    || add score_file_sane 0 "${sc_det:0:300}"
fi

# --- has_good_sol ---
ngood=0; [[ -d "$PKG/sols/good" ]] && ngood="$(find "$PKG/sols/good" -maxdepth 1 -type f 2>/dev/null | wc -l)"
(( ngood >= 1 )) && add has_good_sol 1 "$ngood" || add has_good_sol 0 "sols/good vazio"

# --- good_sol_accepts: precisa de um SANDBOX REAL p/ rodar as soluções. Sob fbwrap (o no-op do
#     firejail, ex.: o servidor de dev) NÃO dá p/ executar de verdade -> DEFERE p/ a calibração,
#     que roda num juiz real e só gera TL se a good é aceita. (Evita falso "Compilation Error".) ---
real_sandbox=false
command -v bwrap >/dev/null 2>&1 && ! bwrap --version 2>&1 | grep -qi fbwrap && real_sandbox=true
if [[ "$VALIDATE_RUN_SOLS" != 0 ]] && (( ngood >= 1 )) && [[ "$real_sandbox" == true ]]; then
  bad=""
  for sol in "$PKG/sols/good/"*; do
    [[ -f "$sol" ]] || continue
    lang="$(bash "$SELF/lang-canon.sh" "${sol##*.}")"   # cc/cxx/c++ -> cpp, py3 -> py
    verdict="$(bash "$SELF/build-and-test.sh" "$lang" "$sol" "$PKG" y 2>/dev/null | tail -n1)"
    [[ "$verdict" =~ ^Accepted ]] || bad+="$(basename "$sol"):${verdict:-?} "
  done
  [[ -z "$bad" ]] && add good_sol_accepts 1 "todas Accepted" || add good_sol_accepts 0 "$bad"
elif (( ngood >= 1 )); then
  add good_sol_accepts 1 "verificado na calibração (juiz)"   # sem sandbox real aqui -> defere
fi

# --- conf_parallel_sane: as chaves de paralelismo do conf (cdmoj/docs/PACOTE.md "Problemas
#     paralelos"), lidas por GREP — conf de autor nunca é sourced aqui. HARD quando o valor é
#     inválido (o juiz cairia no default calado e o TL seria medido de outra forma). Soft:
#     CPUNEEDED>1 sem juiz registrado com essa largura (o problema ficaria esperando p/ sempre).
cpv(){ sed -n "s/^[[:space:]]*$1=[\"']\{0,1\}\([^\"'#[:space:]]*\).*/\1/p" "$PKG/conf" 2>/dev/null | tail -1; }
pbad=""
_cpun="$(cpv CPUNEEDED)"; _snuma="$(cpv SAMENUMA)"; _mpt="$(cpv MAXPARALLELTESTS)"; _apt="$(cpv ALLOWPARALLELTEST)"
[[ -z "$_cpun" || ( "$_cpun" =~ ^[0-9]+$ && "$_cpun" -ge 1 && "$_cpun" -le 64 ) ]] || pbad+="CPUNEEDED=$_cpun (inteiro 1..64) "
[[ -z "$_snuma" || "$_snuma" =~ ^[yn]$ ]] || pbad+="SAMENUMA=$_snuma (y|n) "
[[ -z "$_mpt" || ( "$_mpt" =~ ^[0-9]+$ && "$_mpt" -ge 1 ) ]] || pbad+="MAXPARALLELTESTS=$_mpt (inteiro >= 1) "
[[ -z "$_apt" || "$_apt" =~ ^[yn]$ ]] || pbad+="ALLOWPARALLELTEST=$_apt (y|n) "
if [[ -n "$pbad" ]]; then add conf_parallel_sane 0 "valor inválido no conf: $pbad"
else
  add conf_parallel_sane 1 "${_cpun:+CPUNEEDED=$_cpun }${_snuma:+SAMENUMA=$_snuma }${_mpt:+MAXPARALLELTESTS=$_mpt }${_apt:+ALLOWPARALLELTEST=$_apt }"
  # largura pedida × juízes registrados (run/registry; ausente = não sabemos, sem aviso)
  if [[ "${_cpun:-1}" -gt 1 && -d "$RUNDIR/registry" ]]; then
    _fit="$(find "$RUNDIR/registry" -maxdepth 1 -name '*.json' -exec cat {} + 2>/dev/null \
      | jq -s --argjson k "$_cpun" --arg numa "${_snuma:-n}" '
          def ncpus: split(",") | map(if test("-") then (split("-") | ((.[1]|tonumber) - (.[0]|tonumber) + 1)) else 1 end) | add;
          [ .[] | (if $numa == "y" then ([.topology[]? | .cpus | ncpus] | max // .ncpu // 0) else (.ncpu // 0) end) ]
          | map(select(. >= $k)) | length' 2>/dev/null)"
    [[ "$_fit" =~ ^[0-9]+$ && "$_fit" -eq 0 ]] && render_leak="${render_leak}nenhum-juiz-com-${_cpun}-cpus$([[ "${_snuma:-n}" == y ]] && printf '-num-no-numa') "
  fi
fi

# --- conf_function_sane: FUNCTION_LANGS (submissão de FUNÇÃO, cdmoj/docs/PACOTE.md), lida por GREP.
#     HARD: id inválido, ou linguagem listada SEM scripts/<lang>/compile.sh — o editor abriria vazio,
#     o aluno mandaria só a função e, sem o driver, não haveria main (CE garantido). Soft
#     (render_warnings): um compile.sh que escreve um main num heredoc (fn/driver-langs.sh) numa
#     linguagem FORA da lista — o editor mostraria o esqueleto com main e o aluno levaria CE por main
#     duplicado. A heurística só AVISA; quem decide é a linha, declarada pelo autor.
source "$SELF/lang-canon.sh"
_fnraw="$(sed -nE 's/^[[:space:]]*FUNCTION_LANGS=["'"'"']?([^"'"'"'#]*).*/\1/p' "$PKG/conf" 2>/dev/null | tail -1)"
IFS=', ' read -ra _fnl <<<"$_fnraw"
_cdirs=" "
while IFS= read -r _f; do _cdirs+="$(lang_canon "$(basename "$(dirname "$_f")")") "
done < <(find "$PKG/scripts" -mindepth 2 -maxdepth 2 -name compile.sh 2>/dev/null)
fbad=""; _fdecl=" "
for _l in "${_fnl[@]}"; do
  _c="$(lang_canon "$_l")"
  [[ "$_c" =~ ^[a-z0-9]{1,16}$ ]] || { fbad+="'$_l'(id inválido) "; continue; }
  _fdecl+="$_c "
  [[ "$_cdirs" == *" $_c "* ]] || fbad+="$_c(sem scripts/$_c/compile.sh) "
done
if [[ -n "$fbad" ]]; then add conf_function_sane 0 "FUNCTION_LANGS inválida no conf: $fbad"
else add conf_function_sane 1 "$([[ "$_fdecl" != " " ]] && printf 'FUNCTION_LANGS=%s' "$(echo $_fdecl | tr ' ' ',')")"; fi
_fmiss=""
while IFS= read -r _d; do [[ -n "$_d" && "$_fdecl" != *" $_d "* ]] && _fmiss+="${_fmiss:+,}$_d"
done < <(bash "$SELF/fn/driver-langs.sh" "$PKG" 2>/dev/null)
[[ -n "$_fmiss" ]] && render_leak="${render_leak}driver-de-funcao-fora-do-FUNCTION_LANGS($_fmiss) "

# --- tl_present (soft: informativo) ---
tl_present=false; { [[ -f "$PKG/tl" ]] || [[ -f "$PKG/tl.$HOSTNAME" ]]; } && tl_present=true

# --- veredicto do portão: todas as hard precisam passar ---
report="$(printf '%s\n' "${CK[@]}" | jq -s -c \
  --arg id "$ID" --argjson now "$EPOCHSECONDS" \
  --argjson hb "$html_built" --argjson tp "$tl_present" --arg rw "$render_leak" '
  { id:$id, at:$now, checks:., html_built:$hb, tl_present:$tp,
    render_warnings:($rw|gsub("^ +| +$";"")), ok: (map(.ok) | all) }')"
tmp="$VALDIR/.$ID.tmp"; printf '%s' "$report" > "$tmp" && mv -f "$tmp" "$VALDIR/$ID.json"
ok="$(jq -r '.ok' <<<"$report")"

if [[ "$ok" == true ]]; then
  RUNDIR="$RUNDIR" bash "$SELF/gen-problem-json.sh" "$PKG" "$ID" >/dev/null 2>&1 \
    && echo "validate: $ID OK -> indexado" || echo "validate: $ID OK mas indexação falhou" >&2
  exit 0
else
  echo "validate: $ID REPROVADO -> $(jq -rc '[.checks[]|select(.ok==false)|.name] | join(",")' <<<"$report")" >&2
  exit 1
fi
