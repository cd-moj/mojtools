#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#Foobar is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with Foobar.  If not, see <http://www.gnu.org/licenses/>.


#bash build-and-test.sh cpp ribas-ac.cpp sample-problem/
TEMP=$(mktemp)
TOREMOVE=

function sai()
{
  # publica os reports coletados (staging -> dir final; o rename torna a troca "de uma vez"
  # p/ quem lê o dir depois — nunca fica um dir meio-copiado de um run abortado)
  if [[ -n "$CALIBSTAGE" && -d "$CALIBSTAGE" ]]; then
    rm -rf "$CALIBREPORTS" 2>/dev/null
    mv "$CALIBSTAGE" "$CALIBREPORTS" 2>/dev/null || rm -rf "$CALIBSTAGE"
  fi
  # publica o vetor ESTRUTURADO da calibração (.calib-sols.json, atômico): por solução
  # executada, {file,lang,category,verdict,tests:[{name,code,time,tl}]} — o mesmo formato
  # do resultado de submissão normal. O agente o sobe no /judge/calib-report (campo sols).
  if [[ -s "$TEMP.sols.jsonl" ]]; then
    local t; t="$(mktemp "$PROBLEMDIR/.calib-sols.XXXXXX" 2>/dev/null)" \
      && jq -s -c '.' "$TEMP.sols.jsonl" > "$t" 2>/dev/null && [[ -s "$t" ]] \
      && mv -f "$t" "$PROBLEMDIR/.calib-sols.json" 2>/dev/null || rm -f "$t"
  fi
  rm $TEMP
  rm -rf "$TEMP.claim"
  rm -f $TEMP.*
  rm -rf $TOREMOVE
}

# _renv <workdir> <CHAVE> — um valor do report.env do build-and-test (gravado com %q; sem source)
_renv(){ grep -m1 "^$2=" "$1/report.env" 2>/dev/null | cut -d= -f2- | tr -d "'\""; }

# vetor [{name,code,time,tl[,code_alt,tl_alt]}] dos testes de UM workdir do build-and-test — o MESMO formato do
# agent_tests_json do agente do juiz (fonte: log.verdictall + <file>-log.timelog + report.env). UM item por
# teste: o rerun serial de TLE acrescenta outra linha VERDICT[...] do mesmo teste, e vale a ÚLTIMA (antes saíam
# dois itens, e o servidor contava o TLE que o rerun desfez). Na fase pass/slow/wrong, code_alt/tl_alt = o
# veredicto e o TL do OUTRO método (log.verdictalt; TL_LANG_ALT).
sol_tests_json(){  # $1=workdir
  local wb="$1" tl="" tla="" line file t
  local -A CODE=() ALT=(); local -a ORDER=()
  [[ -f "$wb/log.verdictall" ]] || { echo '[]'; return; }
  tl="$(_renv "$wb" TL_LANG)"; tla="$(_renv "$wb" TL_LANG_ALT)"
  while IFS= read -r line; do
    [[ "$line" =~ ^VERDICT\[(.+)\]=(.+)$ ]] || continue
    file="${BASH_REMATCH[1]}"; [[ -n "${CODE[$file]+x}" ]] || ORDER+=("$file")
    CODE[$file]="${BASH_REMATCH[2]}"
  done < "$wb/log.verdictall"
  if [[ -f "$wb/log.verdictalt" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^VERDICTALT\[(.+)\]=(.+)$ ]] && ALT[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
    done < "$wb/log.verdictalt"
  fi
  {
    for file in "${ORDER[@]}"; do
      t=""
      [[ -s "$wb/$file-log.timelog" ]] && \
        t="$(grep -m1 '^real' "$wb/$file-log.timelog" 2>/dev/null | awk '{print $NF}')"
      jq -cn --arg n "$file" --arg c "${CODE[$file]}" --arg t "$t" --arg tl "$tl" --arg ca "${ALT[$file]:-}" --arg tla "$tla" \
        '{name:$n, code:$c, time:($t|tonumber? // null), tl:($tl|tonumber? // null)}
         + (if $ca != "" then {code_alt:$ca, tl_alt:($tla|tonumber? // null)} else {} end)'
    done
  } | jq -s -c '.'
}
# acumula UMA solução no vetor (tests via --slurpfile: nunca dado por argv de jq). `method` = o método dos
# `code` (TL_METHOD do report.env); `etl` = o teto de tempo de cada teste (o servidor sabe quando uma margem
# não pôde ser medida: teste morto no teto, abaixo de b × TL).
sols_add(){  # $1=workdir $2=file $3=lang $4=category $5=verdict
  command -v jq >/dev/null 2>&1 || return 0
  sol_tests_json "$1" > "$TEMP.tests.json"
  jq -cn --arg f "$2" --arg l "$3" --arg cat "$4" --arg v "$5" \
     --arg m "$(_renv "$1" TL_METHOD)" --arg e "$(_renv "$1" ETL)" \
     --slurpfile tests "$TEMP.tests.json" \
     '{file:$f, lang:$l, category:$cat, verdict:$v, tests:($tests[0] // [])}
      + (if $m != "" then {method:$m} else {} end)
      + (($e|tonumber? // null) as $x | if $x != null then {etl:$x} else {} end)' \
     >> "$TEMP.sols.jsonl" 2>/dev/null
  rm -f "$TEMP.tests.json"
}
# alt_line <workdir> — o resumo da solução pelo OUTRO método (log.verdictalt; vale a última linha de cada teste)
alt_line(){
  local wb="$1" line f v out="" k
  local -A A=() N=()
  [[ -f "$wb/log.verdictalt" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" =~ ^VERDICTALT\[(.+)\]=(.+)$ ]] && A[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
  done < "$wb/log.verdictalt"
  for f in "${!A[@]}"; do v="${A[$f]}"; N[$v]=$(( ${N[$v]:-0} + 1 )); done
  for k in AC AC,PE WA TLE MLE RE RE_NZEC TMT UE; do [[ -n "${N[$k]:-}" ]] && out+="${out:+ · }$k ${N[$k]}"; done
  echo "Pelo método $(_renv "$wb" TL_METHOD_ALT) (TL $(_renv "$wb" TL_LANG_ALT)s): $out"
}

trap sai EXIT


PROBLEMDIR=$(realpath $1)

cd $(dirname $0)
source ./lang-canon.sh   # extensão -> linguagem canônica (cc/cxx/c++ = cpp, py2/py3 = py)
source ./tl-methods.sh   # os métodos de TL: kattis_params, tl_kattis (o MOJ fica aqui embaixo, intocado)

if [[ ! -e build-and-test.sh ]]; then
  stat build-and-test.sh
  exit 1
fi

declare -A ULIMITS TLMOD TLOVERRIDE
[[ -e $PROBLEMDIR/conf ]] && source $PROBLEMDIR/conf

# A tabela de TL de trabalho é PRIVADA ($TEMP.tl, via MOJ_TLFILE): o dummy inicial e a tabela
# em construção NUNCA tocam o diretório compartilhado do problema — outro slot do juiz julgando
# o MESMO problema jamais enxerga placeholder/tabela parcial (era a raiz de veredicto errado
# com calibrações concorrentes). O tl.<host>/tl finais são publicados ATOMICAMENTE (mktemp+mv).
HOSTNAME="${HOSTNAME:-$(hostname)}"
TLHOST="$PROBLEMDIR/tl.$HOSTNAME"
[[ -z "$CALIBRATIONTL" ]] && CALIBRATIONTL=5
CALTL="$TEMP.tl"
# a metade Kattis do fictício (mesmo TL): problema com TLMETHOD=kattis roda as good sem o aviso de tabela sem
# TLKATTIS do build-and-test
printf 'TL[default]=%s\ndeclare -A TLKATTIS\nTLKATTIS[default]=%s\n' "$CALIBRATIONTL" "$CALIBRATIONTL" > "$CALTL"
export MOJ_TLFILE="$CALTL"       # build-and-test filhos leem daqui (vence tl.<host>/tl)
export MOJ_CALIBRATING=1         # a CALIBRAÇÃO mede de verdade: TLOVERRIDE não se aplica aqui
# UM teste por vez, em k CPUs (CPUNEEDED): o TL é medido na MESMA forma em que o julgamento roda
# cada teste. O `export ALLOWPARALLELTEST=n` de antes era vencido pelo conf do pacote (sourced
# depois) — a calibração rodava testes em paralelo sem querer (bug (f), 24/09/2026). A env do
# agente (MOJ_TEST_CPUS/MOJ_CPU_GROUPS, largura k) atravessa; MOJ_PARALLEL é sempre 1 aqui.
export MOJ_PARALLEL=1
# A calibração NUNCA libera grupo de CPU ao agente (26/10/2026). A calibração disparada por um JOB herdava o
# MOJ_RELEASE_FILE dele, e cada build-and-test filho anotava os grupos ≥ 1 como livres ao fim do seu pool
# (_release_group): o agente devolvia ao escalonador os slots que o job ainda ia usar para julgar.
unset MOJ_RELEASE_FILE
# temps de um run morto (kill -9) + o vetor estruturado ANTERIOR: sols é sempre da calibração
# corrente — run abortado deixa sols AUSENTE (o agente não o manda e o servidor preserva/zera
# pelo checksum), nunca dado velho com cara de novo
rm -f "$PROBLEMDIR"/.tl.* "$PROBLEMDIR"/.calib-sols.* "$PROBLEMDIR/.calib-sols.json" 2>/dev/null

# coleta o report.html de cada solução (o agente sobe ao MOJ p/ o autor abrir no editor).
# Coleta em STAGING; o dir final só troca no fim (sai/EXIT) — run abortado não deixa o
# .calib-reports pela metade nem apaga os reports da calibração anterior no meio do voo.
CALIBREPORTS="$PROBLEMDIR/.calib-reports"
rm -rf "$CALIBREPORTS".staging.* 2>/dev/null
CALIBSTAGE="$CALIBREPORTS.staging.$$"; mkdir -p "$CALIBSTAGE" 2>/dev/null
save_report(){ [[ -s "$1/report.html" ]] && cp "$1/report.html" "$CALIBSTAGE/$2.html" 2>/dev/null; }

# find -ac solutions
WORSTTIME=0.01
declare -A WORSTTIMEPERLANG
declare -A LANGOK          # linguagens que tiveram >=1 solução good Accepted neste host

# VALIDADOR DE ENTRADA (scripts/validator.cpp, testlib): só na calibração COMPLETA (o modo rápido é o da
# 1ª submissão — não pode atrasar julgamento). A linha vai no MESMO vetor das soluções (category
# "validator"): o agente sobe o `sols` inteiro e o servidor a separa (lib/calib-expect.sh) — nenhuma
# mudança no agente. Tem orçamento próprio (testlib/validator-run.sh), então não come o teto da calibração.
if [[ -z "$CALIBRATE_ONLY_GOOD" ]]; then
  VJ="$(bash "$PWD/testlib/validator-run.sh" "$PROBLEMDIR" 2>/dev/null)"
  if jq -e '.category == "validator"' >/dev/null 2>&1 <<<"$VJ"; then
    printf '%s\n' "$VJ" >> "$TEMP.sols.jsonl"
    echo "Input validator: $(jq -r '.verdict + (if (.tests|length) > 0 then " (\([.tests[] | select(.code != "OK")] | length) de \(.tests|length) entradas reprovadas)" else "" end)' <<<"$VJ")"
    jq -r '.tests[] | select(.code != "OK") | "  \(.name): \(.code) \(.msg)"' <<<"$VJ" | head -20
    echo
  fi
fi

# ===== RAIAS (26/10/2026; pedido do Ribas: a calibração roda as soluções do mesmo tipo em paralelo) ============
# MOJ_CALIB_LANES — o agente procura este nome aqui p/ saber que o calibreitor tem raias; MOJ_CALIB_LANES=0 no
# ambiente desliga (uma raia só, qualquer que seja o nº de grupos).
# As raias são os grupos de CPU do agente (MOJ_CPU_GROUPS="g0|g1|…"; vazio/ausente = 1 raia, o caminho de sempre).
# Cada raia é uma subshell pinada no seu grupo que reivindica soluções por `mkdir $TEMP.claim/<i>` (o padrão do
# pool do build-and-test) e roda um build-and-test com MOJ_CPU_GROUPS=<o grupo> e MOJ_PARALLEL=1: cada SOLUÇÃO
# segue rodando um teste por vez em k CPUs, a forma do julgamento. Duas fases com barreira: as good (a tabela de TL
# sai delas) e depois pass+slow+wrong (julgadas pela tabela nova). Só o PAI, em ordem, lê os resultados, calcula W e
# LANGOK e grava os arquivos comuns (report, vetor `sols`): o log sai igual ao serial, só que no fim da fase.
CALIB_GROUPS=()
if [[ -n "${MOJ_CPU_GROUPS+x}" ]]; then
  _cg="${MOJ_CPU_GROUPS}"
  while :; do CALIB_GROUPS+=("${_cg%%|*}"); [[ "$_cg" == *"|"* ]] || break; _cg="${_cg#*|}"; done
else
  CALIB_GROUPS=("")
fi
[[ "${MOJ_CALIB_LANES:-1}" == 0 ]] && CALIB_GROUPS=("${CALIB_GROUPS[0]}")

# _run_phase <runall> <solução…> : roda as soluções em L = min(grupos, soluções) raias e espera todas (barreira).
# Deixa $TEMP.item.<i>.out (o stdout do build-and-test: 1ª linha = workdir, última = veredicto) p/ o pai.
_run_phase(){
  local runall="$1"; shift
  local -a items=("$@"); local n=${#items[@]} L=${#CALIB_GROUPS[@]} li
  local -a pids=()
  (( n == 0 )) && return 0
  (( L > n )) && L=$n
  rm -rf "$TEMP.claim"; mkdir -p "$TEMP.claim"
  for (( li=0; li<L; li++ )); do
    ( trap - EXIT          # a raia nunca publica nem apaga nada (o sai() é do pai)
      g="${CALIB_GROUPS[li]}"
      (( L > 1 )) && [[ -n "$g" ]] && taskset -pc "$g" $BASHPID >/dev/null 2>&1
      for (( i=0; i<n; i++ )); do
        mkdir "$TEMP.claim/$i" 2>/dev/null || continue
        f="${items[i]}"; lg="$(lang_canon "${f##*.}")"
        if (( L > 1 )); then
          MOJ_CPU_GROUPS="$g" MOJ_PARALLEL=1 bash build-and-test.sh "$lg" "$f" "$PROBLEMDIR" "$runall" \
            > "$TEMP.item.$i.out" 2> "$TEMP.item.$i.err"
        else
          bash build-and-test.sh "$lg" "$f" "$PROBLEMDIR" "$runall" > "$TEMP.item.$i.out" 2> "$TEMP.item.$i.err"
        fi
      done ) &
    pids+=($!)
  done
  wait "${pids[@]}" 2>/dev/null
  return 0
}
# _item_tv <i> : T (o workdir) e A (o veredicto) da solução i, como o agente lê o build-and-test (1ª e última
# linha). Build-and-test morto antes do veredicto (a última linha é o próprio workdir) = A vazio.
_item_tv(){
  T="$(head -n1 "$TEMP.item.$1.out" 2>/dev/null)"; A="$(tail -n1 "$TEMP.item.$1.out" 2>/dev/null)"
  [[ "$A" == "$T" || -d "$A" ]] && A=""
  return 0
}
# _exectimes <workdir> : as linhas EXECTIME do trace (ancorado: o trace copia o stderr da solução, e uma linha
# "… EXECTIME x 0.01 AC" no meio dela não é tempo), "<tempo> <código>" por linha
_exectimes(){
  local _ln _a _b et sr
  [[ -n "$1" && -f "$1/run-trace.log" ]] || return 0
  while IFS= read -r _ln; do
    [[ "$_ln" =~ ^EXECTIME[[:space:]] ]] || continue
    read -r _a _b et sr <<< "$_ln"
    printf '%s %s\n' "$et" "$sr"
  done < "$1/run-trace.log"
}

echo "AC solutions:"
export ALLOWPARALLELTEST=n
GOODS=()
for AC in $PROBLEMDIR/sols/good/*; do [[ -e "$AC" ]] && GOODS+=("$AC"); done
_run_phase "$ALLOWTLEDURINGCALIBRATION" "${GOODS[@]}"
for i in "${!GOODS[@]}"; do
  AC="${GOODS[i]}"
  echo "${AC##*/}:"
  # extensão -> linguagem canônica (lang-canon.sh): py2/py3 legadas = py; cc/cxx/c++ = cpp.
  # Chave ÚNICA na tabela de TL — e é o canônico que vai ao build-and-test (era a extensão crua).
  LANG="$(lang_canon "${AC##*.}")"
  [[ ! -n "${WORSTTIMEPERLANG[$LANG]}" ]] && WORSTTIMEPERLANG[$LANG]=0.01
  _item_tv "$i"
  while read -r ET SMALLRESP; do
    printf ' %s' "$ET"
    [[ "$SMALLRESP" != "AC" ]] && printf '(%s)' "$SMALLRESP"
    if [[ "$SMALLRESP" =~ "AC" ]] && echo "$ET > ${WORSTTIMEPERLANG[$LANG]}"|bc |grep -q 1; then
      WORSTTIMEPERLANG[$LANG]=$ET
    fi
  done < <(_exectimes "$T")
  echo

  if [[ "${A}" =~ "Accepted" ]]; then
    LANGOK[$LANG]=1
  elif [[ "${A}" =~ "Time Limit Exceeded" && "$ALLOWTLEDURINGCALIBRATION" == "y" ]]; then
    LANGOK[$LANG]=1
  else
    # ROBUSTEZ: NÃO aborta a calibração inteira por uma solução (toolchain ausente no
    # juiz, erro de ambiente, ou solução realmente quebrada). Segue — o juiz reporta a falha
    # ao MOJ (visível sem ssh). Só emite TL p/ linguagens em que ALGUMA good passou: se outra
    # good da mesma linguagem foi aceita, a linguagem calibra (a mensagem dizia "NÃO
    # calibrada" mesmo assim). Quem diz quais linguagens ficaram sem TL é o resumo no fim.
    # ⚠ "was waiting Accepted" é contrato: o agente do juiz conta as falhas por essa frase.
    echo "$AC got '${A:-<sem veredito>}', was waiting Accepted. Check ${T}"
  fi
  echo "Verdict: $A"
  echo
  save_report "$T" "good-${AC##*/}"
  sols_add "$T" "${AC##*/}" "$LANG" good "$A"
  TOREMOVE+=" ${T}"
done

TLMULT=1.35

[[ -n "${TLMOD[calibrafactor]}" ]] && TLMULT=${TLMOD[calibrafactor]}

BESTTIME=10000
# W[lang] CRU (o pior tempo de teste AC das good) — o laço do MOJ abaixo troca o valor pelo TL; o Kattis usa este
declare -A WRAW
for t in ${!WORSTTIMEPERLANG[@]}; do WRAW[$t]="${WORSTTIMEPERLANG[$t]}"; done

# monta a tabela FINAL na cópia privada; o dir compartilhado só vê o resultado completo
echo "#Generated by calibreitor on $HOSTNAME ($(date -R))" > "$CALTL"

for t in ${!WORSTTIMEPERLANG[@]}; do
  [[ -n "${LANGOK[$t]}" ]] || continue     # só emite TL p/ linguagens que passaram aqui
  WORSTTIMEPERLANG[$t]="$(echo "$TLMULT * ${WORSTTIMEPERLANG[$t]} + 0.02"|bc -l)"
  echo "TL[$t]=${WORSTTIMEPERLANG[$t]}" >> "$CALTL"
  if echo "${WORSTTIMEPERLANG[$t]} < $BESTTIME"|bc|grep -q 1; then
    BESTTIME=${WORSTTIMEPERLANG[$t]}
  fi
done

# nenhuma linguagem calibrou (todas faltaram/falharam) -> fallback sensato, não 10000
[[ "$BESTTIME" == 10000 ]] && BESTTIME="$CALIBRATIONTL"
echo "TL[default]=$BESTTIME" >> "$CALTL"

# MÉTODO KATTIS (spec 2025-09, por linguagem — decisão do Ribas, 26/10/2026; tl-methods.sh): o menor múltiplo de
# r que é ≥ a × W[lang], com o MESMO W[lang] do MOJ; default = o menor, como no MOJ. A tabela leva as DUAS
# metades sempre; quem escolhe é o TLMETHOD do conf, no julgamento. O `declare -A` vai DENTRO do arquivo: o
# agente do juiz faz `source` dele sob `set -u` declarando só TL/TLMOD, e sem isto a reportagem morreria.
read -r KATTIS_A KATTIS_B KATTIS_R < <(kattis_params)
declare -A TLK
KBEST=""
for t in ${!WRAW[@]}; do
  [[ -n "${LANGOK[$t]}" ]] || continue
  TLK[$t]="$(tl_kattis "${WRAW[$t]}" "$KATTIS_A" "$KATTIS_R")"
  if [[ -z "$KBEST" ]] || echo "${TLK[$t]} < $KBEST" | bc | grep -q 1; then KBEST="${TLK[$t]}"; fi
done
{
  echo "# Kattis 2025-09: o menor múltiplo de r >= a x pior AC, por linguagem (a=$KATTIS_A r=$KATTIS_R); default = o menor"
  echo "declare -A TLKATTIS"
  for t in ${!TLK[@]}; do echo "TLKATTIS[$t]=${TLK[$t]}"; done
  echo "TLKATTIS[default]=${KBEST:-$CALIBRATIONTL}"
} >> "$CALTL"

# PUBLICAÇÃO ATÔMICA (mktemp no MESMO fs + mv): leitor concorrente (submissão noutro slot
# fazendo `source tl.<host>`) vê SEMPRE uma tabela completa — a anterior ou esta, nunca
# um arquivo pela metade nem o dummy TL[default] do início da calibração.
publish_tl(){
  local t; t="$(mktemp "$PROBLEMDIR/.tl.XXXXXX")" || return 1
  cp "$CALTL" "$t" && mv -f "$t" "$1" || { rm -f "$t"; return 1; }
}
publish_tl "$TLHOST"
# tl genérico = fallback p/ hosts sem calibração própria
publish_tl "$PROBLEMDIR/tl"

echo "Calibrated TL ($HOSTNAME):"
tail -n+1 "$TLHOST"
for t in ${!TLK[@]}; do
  echo "Kattis: $t $KATTIS_A × ${WRAW[$t]} = $(echo "$KATTIS_A * ${WRAW[$t]}" | LC_ALL=C bc -l | _tlm_clean) → ${TLK[$t]} s (resolução $KATTIS_R s)"
done
for t in ${!WORSTTIMEPERLANG[@]}; do
  [[ -n "${LANGOK[$t]}" ]] || echo "linguagem $t NÃO calibrada neste host (nenhuma solução good $t foi aceita)"
done

# Modo rápido (calibração sob demanda no modelo cache): só as good bastam p/ o TL.
# Pular pass/slow/wrong evita rodar dezenas de soluções/linguagens a cada 1ª submissão.
if [[ -n "$CALIBRATE_ONLY_GOOD" ]]; then
  echo; echo "(CALIBRATE_ONLY_GOOD: pulando verificação verbose de pass/slow/wrong)"
  exit 0
fi

# pass/slow/wrong: o build-and-test julga pelo método do conf E TAMBÉM pelo outro (MOJ_CALIB_ALT): o veredicto
# alternativo de cada teste vai p/ o log.verdictalt e o vetor estruturado (code_alt/tl_alt); trocar o método no
# conf não perde o juízo das soluções.
export MOJ_CALIB_ALT=1
OTHERS=(); OCATS=()
for OTHERSOL in pass slow wrong; do
  [[ -d "$PROBLEMDIR/sols/$OTHERSOL" ]] || continue
  for TLs in $PROBLEMDIR/sols/$OTHERSOL/*; do [[ -e "$TLs" ]] && { OTHERS+=("$TLs"); OCATS+=("$OTHERSOL"); }; done
done
_run_phase y "${OTHERS[@]}"
i=0
for OTHERSOL in pass slow wrong; do
  [[ ! -d "$PROBLEMDIR/sols/$OTHERSOL" ]] && continue
  echo
  echo "${OTHERSOL^^} solutions:"
  nsol=0
  while (( i < ${#OTHERS[@]} )) && [[ "${OCATS[i]}" == "$OTHERSOL" ]]; do
    TLs="${OTHERS[i]}"
    echo "${TLs##*/}:"
    LANG="$(lang_canon "${TLs##*.}")"
    _item_tv "$i"
    while read -r ET SMALLRESP; do printf '%s(%s) ' "$ET" "$SMALLRESP"; done < <(_exectimes "$T")
    echo
    BIGRESP="$A"
    echo "Verdict: $BIGRESP"
    alt_line "$T"
    save_report "$T" "$OTHERSOL-${TLs##*/}"
    sols_add "$T" "${TLs##*/}" "$LANG" "$OTHERSOL" "$BIGRESP"
    TOREMOVE+=" ${T}"
    i=$((i+1)); nsol=$((nsol+1))
  done
  (( nsol == 0 )) && echo none
done
