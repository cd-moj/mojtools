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
  rm -f $TEMP.*
  rm -rf $TOREMOVE
}

# vetor [{name,code,time,tl}] dos testes de UM workdir do build-and-test — o MESMO formato do
# agent_tests_json do agente do juiz (fonte: log.verdictall + <file>-log.timelog + report.env).
sol_tests_json(){  # $1=workdir
  local wb="$1" tl="" line file code t
  [[ -f "$wb/log.verdictall" ]] || { echo '[]'; return; }
  tl="$(grep -m1 '^TL_LANG=' "$wb/report.env" 2>/dev/null | cut -d= -f2- | tr -d "'\"")"
  {
    while IFS= read -r line; do
      [[ "$line" =~ ^VERDICT\[(.+)\]=(.+)$ ]] || continue
      file="${BASH_REMATCH[1]}"; code="${BASH_REMATCH[2]}"
      t=""
      [[ -s "$wb/$file-log.timelog" ]] && \
        t="$(grep -m1 '^real' "$wb/$file-log.timelog" 2>/dev/null | awk '{print $NF}')"
      jq -cn --arg n "$file" --arg c "$code" --arg t "$t" --arg tl "$tl" \
        '{name:$n, code:$c, time:($t|tonumber? // null), tl:($tl|tonumber? // null)}'
    done < "$wb/log.verdictall"
  } | jq -s -c '.'
}
# acumula UMA solução no vetor (tests via --slurpfile: nunca dado por argv de jq)
sols_add(){  # $1=workdir $2=file $3=lang $4=category $5=verdict
  command -v jq >/dev/null 2>&1 || return 0
  sol_tests_json "$1" > "$TEMP.tests.json"
  jq -cn --arg f "$2" --arg l "$3" --arg cat "$4" --arg v "$5" \
     --slurpfile tests "$TEMP.tests.json" \
     '{file:$f, lang:$l, category:$cat, verdict:$v, tests:($tests[0] // [])}' \
     >> "$TEMP.sols.jsonl" 2>/dev/null
  rm -f "$TEMP.tests.json"
}

trap sai EXIT


PROBLEMDIR=$(realpath $1)

cd $(dirname $0)

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
echo "TL[default]=$CALIBRATIONTL" > "$CALTL"
export MOJ_TLFILE="$CALTL"       # build-and-test filhos leem daqui (vence tl.<host>/tl)
export MOJ_CALIBRATING=1         # a CALIBRAÇÃO mede de verdade: TLOVERRIDE não se aplica aqui
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

echo "AC solutions:"
for AC in $PROBLEMDIR/sols/good/*; do
  echo "${AC##*/}:"
  LANG=${AC##*.}
  # python unificado: sols .py2/.py3 legadas contam como 'py' (chave única na tabela de TL)
  case "$LANG" in py2|py3) LANG=py;; esac
  [[ ! -n "${WORSTTIMEPERLANG[$LANG]}" ]] && WORSTTIMEPERLANG[$LANG]=0.01

  mkfifo $TEMP.coprocout
  export ALLOWPARALLELTEST=n
  coproc bash build-and-test.sh ${AC##*.} $AC $PROBLEMDIR $ALLOWTLEDURINGCALIBRATION &>$TEMP.coprocout
  #read -u ${COPROC[0]} T
  exec 7<$TEMP.coprocout
  read -u 7 T
  while read L; do
    [[ "$L" =~ "EXECTIME" ]] || continue;
    read l l ET SMALLRESP <<< "$L"
    printf " $ET"
    [[ "$SMALLRESP" != "AC" ]] && printf "($SMALLRESP)"
    if [[ "$SMALLRESP" =~ "AC" ]] && echo "$ET > ${WORSTTIMEPERLANG[$LANG]}"|bc |grep -q 1; then
      WORSTTIMEPERLANG[$LANG]=$ET
    fi
  done <<< $(tail -f --pid=$COPROC_PID $T/run-trace.log)
  echo

  read -u 7 A
  if [[ "${A}" =~ "Accepted" ]]; then
    LANGOK[$LANG]=1
  elif [[ "${A}" =~ "Time Limit Exceeded" && "$ALLOWTLEDURINGCALIBRATION" == "y" ]]; then
    LANGOK[$LANG]=1
  else
    # ROBUSTEZ: NÃO aborta a calibração inteira por uma solução (toolchain ausente no
    # juiz, erro de ambiente, ou solução realmente quebrada). Pula a linguagem e segue —
    # o juiz reporta a falha ao MOJ (visível sem ssh). Só emite TL p/ linguagens que passaram.
    echo "$AC got '${A:-<sem veredito>}', was waiting Accepted (linguagem $LANG NÃO calibrada neste host). Check ${T}"
  fi
  echo "Verdict: $A"
  echo
  save_report "$T" "good-${AC##*/}"
  sols_add "$T" "${AC##*/}" "$LANG" good "$A"
  TOREMOVE+=" ${T}"
  exec 7<&-
  rm -f $TEMP.coprocout
done

TLMULT=1.35

[[ -n "${TLMOD[calibrafactor]}" ]] && TLMULT=${TLMOD[calibrafactor]}

BESTTIME=10000

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

# Modo rápido (calibração sob demanda no modelo cache): só as good bastam p/ o TL.
# Pular pass/slow/wrong evita rodar dezenas de soluções/linguagens a cada 1ª submissão.
if [[ -n "$CALIBRATE_ONLY_GOOD" ]]; then
  echo; echo "(CALIBRATE_ONLY_GOOD: pulando verificação verbose de pass/slow/wrong)"
  exit 0
fi

for OTHERSOL in pass slow wrong; do
  [[ ! -d "$PROBLEMDIR/sols/$OTHERSOL" ]] && continue
  echo
  echo "${OTHERSOL^^} solutions:"
  for TLs in $PROBLEMDIR/sols/$OTHERSOL/*; do
    if [[ ! -e $TLs ]]; then echo none; continue;fi
    echo "${TLs##*/}:"
    LANG="${TLs##*.}"
    case "$LANG" in py2|py3) LANG=py;; esac
    mkfifo $TEMP.coproc
    coproc bash build-and-test.sh ${TLs##*.} $TLs $PROBLEMDIR y >$TEMP.coproc
    exec 7<$TEMP.coproc
    read -u 7 T
    tail -f --pid=$COPROC_PID $T/run-trace.log|
      while read L; do
        [[ "$L" =~ "EXECTIME" ]] || continue;
        read l l ET SMALLRESP <<< "$L"
        printf "$ET($SMALLRESP) "
      done
    echo
    read -u 7 BIGRESP
    echo "Verdict: $BIGRESP"
    save_report "$T" "$OTHERSOL-${TLs##*/}"
    sols_add "$T" "${TLs##*/}" "$LANG" "$OTHERSOL" "$BIGRESP"
    exec 7<&-
    rm -f $TEMP.coproc
    TOREMOVE+=" ${T}"
  done
done
