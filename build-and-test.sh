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


function LOG()
{
  echo "$*" >&2
}

SELFDIR="$(cd "$(dirname "$0")" && pwd)"

# escreve os metadados que o gen-report.sh consome (mapa VERDICT vem de
# log.verdictall; o resto, daqui). $1 = REPORTMODE (normal|ce)
function write_report_env()
{
  {
    # id real do problema (no modelo cache o pacote vive em <id>/pkg, então basename="pkg";
    # o juiz passa MOJ_PROBLEM_ID com o id correto).
    printf 'PROBLEM=%q\n'            "${MOJ_PROBLEM_ID:-$(basename "$PROBLEMTEMPLATEDIR")}"
    printf 'LANGUAGE=%q\n'           "$LANGUAGE"
    printf 'TOOLCHAIN_ROOT=%q\n'     "${CAGE_ROOT:-sistema do host}"
    printf 'TOOLCHAIN_VER=%q\n'      "${TOOLCHAIN_VER:-}"
    printf 'SRCBASENAME=%q\n'        "$(basename "$SRCCODE")"
    printf 'TL_LANG=%q\n'            "${TL[$LANGUAGE]:-}"
    printf 'SMALLRESP=%q\n'          "${SMALLRESP:-}"
    printf 'FINALRESP=%q\n'          "${FINALRESP:-}"
    # veredicto CANÔNICO limpo (sem score) + score estruturado, p/ o backend casar/montar strings
    printf 'VERDICT_CANON=%q\n'      "${VERDICT_CANON:-}"
    printf 'SCORE=%q\n'              "${SCORE:-0}"
    printf 'SCORE_MAX=%q\n'          "${SCORE_MAX:-100}"
    printf 'SCORE_KIND=%q\n'         "${SCORE_KIND:-tests}"
    # grupos (subtasks) estruturados: JSON [{"earned":N|null,"max":N},...] na ordem do
    # tests/score, só grupos de peso>0; vazio = sem grupos (score-summary.sh)
    printf 'SCORE_GROUPS=%q\n'       "${SCORE_GROUPS:-}"
    printf 'CORRECT=%q\n'            "${CORRECT:-0}"
    printf 'TOTALTESTS=%q\n'         "${TOTALTESTS:-0}"
    printf 'TOTALTIME=%q\n'          "${TOTALTIME:-0}"
    printf 'PROBLEMTEMPLATEDIR=%q\n' "${PROBLEMTEMPLATEDIR:-}"
    printf 'HOSTBT=%q\n'             "${HOSTNAME:-}"
    printf 'STARTDATE=%q\n'          "${STARTDATE:-}"
    printf 'RUNALL=%q\n'             "${RUNALL:-}"
    printf 'NPROCINFO=%q\n'          "${NPROC:-}"
    printf 'REPORTMODE=%q\n'         "${1:-normal}"
  } > "$workdirbase/report.env"
}

# gera report.org + report.html (auto-contido). Toda saída vai para o trace —
# nunca para stdout, que carrega o contrato do veredicto lido pelo agente do juiz.
function gen_report()
{
  write_report_env "${1:-normal}"
  bash "$SELFDIR/gen-report.sh" "$workdirbase" >> "$workdirbase/run-trace.log" 2>&1
}

# coleta a VERSÃO do toolchain (compilador/interpretador) RODANDO DENTRO DA JAULA — reflete o
# que de fato compilou/rodou (host ou rootfs via CAGE_ROOT). Só p/ submissões reais (o juiz
# manda MOJ_PROBLEM_ID); pulado na calibração p/ não pagar uma jaula extra por solução.
declare -A _VERCMD=(
  [c]="gcc --version" [cpp]="g++ --version" [java]="javac -version" [py]="python3 --version"
  [go]="gccgo --version" [rs]="rustc --version" [hs]="ghc --version" [cs]="mcs --version"
  [pas]="fpc -iV" [pl]="swipl --version" [js]="node --version" [ml]="ocamlopt -version"
  [spim]="spim -version" [sh]="bash --version" [riscv]="java -version"
  [kt]="kotlinc -version"
)
collect_toolchain()
{
  TOOLCHAIN_VER=""
  [[ -n "${MOJ_PROBLEM_ID:-}" ]] || return 0
  local vc="${_VERCMD[$LANGUAGE]:-}"; [[ -n "$vc" ]] || return 0
  local vs="$workdirbase/.ver.sh"
  printf '#!/bin/bash\n%s 2>&1 | head -2\n' "$vc" > "$vs"; chmod +x "$vs"
  TOOLCHAIN_VER="$(bash cage-run.sh $CAGEROOTARG -w $workdir -r "$vs" $SHIELDPARAMS $EXTRABINDINGS \
      -s "$workdirbase/.vers" -t "$workdirbase/.vert" -T 10 -B "$workdirbase/.verb" 2>/dev/null \
      | tr '\n' ' ' | sed 's/  */ /g')"; TOOLCHAIN_VER="${TOOLCHAIN_VER:0:250}"
}

if [[ ! -n "$3" ]]; then
  echo "$0 <LANGUAGE> <SRCFILE> <PROBLEMTEMPLATEDIR> [<RUNALL?y:n>]"
  exit 1
fi

LANGUAGE=$1
# python unificado: 'py' (pypy3). py2/py3 são extensões LEGADAS (submissões antigas,
# sols de pacotes) — normaliza aqui p/ o lang-dir, o TL e o _VERCMD verem só 'py'.
case "$LANGUAGE" in py2|py3) LANGUAGE=py;; esac
SRCCODE=$(realpath $2)
PROBLEMTEMPLATEDIR=$(realpath $3)
RUNALL=$4
RUNALL=${RUNALL:=no}

workdirbase=$(mktemp -d)
workdir=$workdirbase/cagefiles/

if [[ ! -e "$workdirbase" ]]; then
  echo "Could not create $workdirbase"
  exit 1
fi

exec 2> $workdirbase/run-trace.log

LOG "% Running: $(basename $PROBLEMTEMPLATEDIR)"
LOG ""
LOG "- Minimal Information"
LOG "  - Submission Language: $LANGUAGE"
LOG "  - Submission SRCFILE: $(basename $SRCCODE)"
LOG "  - Run all even on critical error: $RUNALL"
LOG ""
STARTDATE="$(date -R)"
LOG "- Starting at $STARTDATE"
LOG "- Running on host '$HOSTNAME'"
LOG ""

STARTTIME=$EPOCHSECONDS
mkdir -p $workdir
echo $workdirbase

cd $(dirname $0)

cp "$SRCCODE" $workdir/

declare -a BIN

declare -A ULIMITS
declare -A TLMOD

DEFAULTSHIELDCPU=3
DEFAULTSHIELDUSER=judge
DEFAULTMEMLIMIT=600

# Raiz da jaula (default: raiz do sistema). Global via env CAGE_ROOT; o conf do problema pode
# sobrescrever; e há override por linguagem via CAGE_ROOT_<LANG> (ex.: CAGE_ROOT_JAVA). Aponta
# p/ um rootfs (ex.: Ubuntu 24.04 com os compiladores) p/ um toolchain reprodutível.
: "${CAGE_ROOT:=}"

#set default values
#configurações de variáveis do ulimit
## stack
### default: 128MB p/ TODAS as linguagens (rlimit herdado através do bwrap; a JVM espelha
### em -Xss via binfile.sh). Override por conf: STACKLIMITMB (MB) ou ULIMITS[-s] (KB).
ULIMITS[-s]=131072

## file size
### default to 100MB
ULIMITS[-f]=256000

## virtual memory
### default to 600MB
#ULIMITS[-v]=614400

## max processes
### default to 1024
ULIMITS[-u]=1024

#check if there is conf
[[ -e $PROBLEMTEMPLATEDIR/conf ]] && source $PROBLEMTEMPLATEDIR/conf

# STACKLIMITMB (MB, simétrico ao MEMLIMITMB) é a forma preferida de mudar a stack no conf;
# vence o ULIMITS[-s] (KB), que segue aceito p/ ajuste fino quando STACKLIMITMB ausente.
[[ "${STACKLIMITMB:-}" =~ ^[0-9]+$ ]] && ULIMITS[-s]=$((STACKLIMITMB*1024))

# Limite de memória por RSS MEDIDO (MEMLIMITMB, em MB) — alternativa ao ulimit -v. Quando o
# conf liga isso, NÃO aplicamos o limite de memória VIRTUAL (que penaliza linguagens que
# reservam heaps enormes — JVM/Go/etc. — sem usar essa memória de fato). O veredito MLE é dado
# comparando o pico de RSS (res %M do /usr/bin/time) com MEMLIMITMB.
[[ -n "${MEMLIMITMB:-}" ]] && unset 'ULIMITS[-v]'

LOG "## LIMITS via ulimits"
LOG ""
#set ulimits
for l in ${!ULIMITS[@]}; do
  ulimit $l ${ULIMITS[$l]}
  LOG "set: ulimit $l ${ULIMITS[$l]}"
done
LOG ""
LOG ""

#default locations
LANGUAGEDIR=lang/$LANGUAGE
PROBLEMLANGUAGEDIR="$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE"
# compat da unificação do python: LANGUAGE já virou 'py' (linha ~98), mas pacote legado tem a
# correção especial em scripts/py3 (ou py2) — sem este fallback o compile/run/compare CUSTOM
# era silenciosamente IGNORADO (function-submission do APC rodava a solução pelada => WA vazio).
if [[ "$LANGUAGE" == py && ! -d "$PROBLEMLANGUAGEDIR" ]]; then
  for _pl in py3 py2; do
    [[ -d "$PROBLEMTEMPLATEDIR/scripts/$_pl" ]] && { PROBLEMLANGUAGEDIR="$PROBLEMTEMPLATEDIR/scripts/$_pl"; break; }
  done
fi
DEFAULTLANGUAGEDIR=$(realpath $LANGUAGEDIR)
#LANGCOMPILE=$(realpath $LANGCOMPILE)

#search for special compile script for problem
#if it does not exist defaults to default language compile
LANGCOMPILE=$PROBLEMLANGUAGEDIR/compile.sh
[[ ! -e "$LANGCOMPILE" ]] && LANGCOMPILE="$DEFAULTLANGUAGEDIR/compile.sh"

if [[ ! -e "$LANGCOMPILE" ]]; then
  echo "Language '$LANGUAGE' not availale"
  LOG "Language '$LANGUAGE' not availale"
  LOG "$LANGCOMPILE not found"
  exit 3
fi

# tempo-limite de COMPILAÇÃO (segundos): default 30; linguagens de compilador lento (JVM
# fria do kotlinc) sobem via arquivo `compile-tl` no lang-dir (problema pode sobrescrever).
COMPILETL=30
if   [[ -f "$PROBLEMLANGUAGEDIR/compile-tl" ]]; then COMPILETL="$(< "$PROBLEMLANGUAGEDIR/compile-tl")"
elif [[ -f "$DEFAULTLANGUAGEDIR/compile-tl" ]]; then COMPILETL="$(< "$DEFAULTLANGUAGEDIR/compile-tl")"
fi
[[ "$COMPILETL" =~ ^[0-9]+$ ]] || COMPILETL=30

# override de raiz da jaula por linguagem: CAGE_ROOT_<LANG> (ex.: CAGE_ROOT_PY, CAGE_ROOT_JAVA)
LANGUC="${LANGUAGE^^}"; LANGUC="${LANGUC//[^A-Z0-9]/_}"
CAGEROOTVAR="CAGE_ROOT_$LANGUC"
[[ -n "${!CAGEROOTVAR:-}" ]] && CAGE_ROOT="${!CAGEROOTVAR}"
export CAGE_ROOT                                    # p/ os prep.sh enxergarem (ex.: pas/prep.sh)
CAGEROOTARG=""; [[ -n "$CAGE_ROOT" ]] && CAGEROOTARG="-R $CAGE_ROOT"
[[ -n "$CAGE_ROOT" ]] && LOG "## CAGE_ROOT=$CAGE_ROOT"

EXTRABINDINGS=
PREPLANGUAGE="$PROBLEMLANGUAGEDIR/prep.sh"
[[ -x "$PREPLANGUAGE" ]] && . $PREPLANGUAGE $workdir
[[ ! -e "$PREPLANGUAGE" ]] && [[ -e "$DEFAULTLANGUAGEDIR/prep.sh" ]] &&
. $DEFAULTLANGUAGEDIR/prep.sh $workdir

# teto DURO de memória (cgroup): max(default, MEMLIMITMB do problema + folga) — a folga de
# 64MB deixa o overhead de runtime (metaspace/threads da JVM) fora do OOM; quem manda no
# veredito MLE continua sendo o RSS medido vs MEMLIMITMB. Vale p/ root (cgroup v1) e sem
# root (cgroup v2 via systemd-run; degrada p/ MLE-por-RSS sem user manager).
HARDMEM=$DEFAULTMEMLIMIT
[[ "${MEMLIMITMB:-}" =~ ^[0-9]+$ ]] && (( MEMLIMITMB + 64 > HARDMEM )) && HARDMEM=$(( MEMLIMITMB + 64 ))
if [[ "$USER" == root ]]; then
  SHIELDPARAMS="--shield-cpu $DEFAULTSHIELDCPU --shield-user $DEFAULTSHIELDUSER -M $HARDMEM"
  COMPILESHIELDPARAMS="--shield-cpu $DEFAULTSHIELDCPU --shield-user $DEFAULTSHIELDUSER -M ${COMPILEMEMLIMIT:-2048}"
else
  # a COMPILAÇÃO ganha teto próprio maior (kotlinc/JVM passam de 600MB — COMPILEMEMLIMIT)
  SHIELDPARAMS="-M $HARDMEM"
  COMPILESHIELDPARAMS="-M ${COMPILEMEMLIMIT:-2048}"
fi

collect_toolchain   # versão do compilador/interpretador na jaula (p/ o report; só submissão real)
[[ -n "${TOOLCHAIN_VER:-}" ]] && LOG "## TOOLCHAIN: $TOOLCHAIN_VER (root=${CAGE_ROOT:-host})"

LOG "# Compiling code"
LOG ""
bash cage-run.sh $CAGEROOTARG -w $workdir -r $LANGCOMPILE ${COMPILESHIELDPARAMS:-$SHIELDPARAMS} $EXTRABINDINGS\
                    -s $workdirbase/compile.log.stderr \
                    -o $workdirbase/compile.log.stdout \
                    -t $workdirbase/compile.log.time \
                    -T $COMPILETL\
                    -B $workdirbase/compile.log.bwraptime &> $workdirbase/compile.log.cage-run

CAGERET=$?

if ! grep -q ^BIN= $workdirbase/compile.log.stdout || (( CAGERET != 0 )) ; then
  LOG "   COMPILATION ERROR"
  LOG ""
  LOG "CE $workdir"
  for f in $workdirbase/compile.log.{stdout,stderr,cage-run,time,bwraptime}; do
    LOG "## $f"
    LOG "$(< $f)"
    LOG ""
  done
  SMALLRESP=CE
  FINALRESP="Compilation Error"
  VERDICT_CANON="Compilation Error"; SCORE=0; SCORE_MAX=100; SCORE_KIND=tests
  gen_report ce
  echo "Compilation Error"
  exit 1
fi
#cut -d'=' -f2 < $workdir/log.stdout
BIN+=( $(cut -d'=' -f2 < $workdirbase/compile.log.stdout) )
# binfile.sh é o canal p/ DENTRO da jaula (todo run.sh faz `source binfile.sh`): além do BIN,
# carrega os limites do problema — a JVM dimensiona -Xmx/-Xss por eles (java/kt/interactive).
{ echo "BIN=${BIN[0]}"
  echo "MOJ_MEMLIMITMB=${MEMLIMITMB:-}"
  echo "MOJ_STACKKB=${ULIMITS[-s]}"
} > $workdir/binfile.sh

LOG ""
LOG ""
LOG "# Running test files"

#search for runner script, first in problem second default
LANGRUN=$PROBLEMLANGUAGEDIR/run.sh
[[ ! -e "$LANGRUN" ]] && LANGRUN=$DEFAULTLANGUAGEDIR/run.sh

#Search for compare script, first: language specific in problem
# second: common in problem
# third: language specific default
# fourth: commom default
LANGCOMPARE=$PROBLEMLANGUAGEDIR/compare.sh
[[ ! -e "$LANGCOMPARE" ]] && LANGCOMPARE=$PROBLEMTEMPLATEDIR/scripts/compare.sh
[[ ! -e "$LANGCOMPARE" ]] && LANGCOMPARE=$DEFAULTLANGUAGEDIR/compare.sh
[[ ! -e "$LANGCOMPARE" ]] && LANGCOMPARE=$(realpath lang/compare.sh)
#LANGCOMPARE=$(realpath $LANGCOMPARE)

#[[ -e "$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE/compare.sh" ]] && LANGCOMPARE="$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE/compare.sh"

if [[ ! -e "$LANGRUN" ]]; then
  echo "Language '$LANGUAGE' not availale"
  LOG "$LANGRUN not found"
  exit 3
fi

if [[ ! -e "$LANGCOMPARE" ]]; then
  echo "Language '$LANGUAGE' not availale"
  LOG "$LANGCOMPARE not found"
  exit 3
fi

declare -A TL
# TL por host: usa tl.<hostname> se existir (calibração específica da máquina,
# calibrada neste host), senão o tl padrão do pacote.
TLFILE="$PROBLEMTEMPLATEDIR/tl"
[[ -e "$PROBLEMTEMPLATEDIR/tl.$HOSTNAME" ]] && TLFILE="$PROBLEMTEMPLATEDIR/tl.$HOSTNAME"
if [[ ! -e "$TLFILE" ]]; then
  echo "Wrong package format. No TimeLimit found"
  LOG "Timelimit is not set"
  exit 3
fi
source $TLFILE
LOG "TL file: $(basename "$TLFILE")"

# shim de compat: tl calibrado antes da unificação do python tem chave py3 (às vezes py2);
# sem isto TL[py] cairia no TL[default] (o MENOR) => falso TLE até recalibrar.
[[ -z "${TL[py]:-}" && -n "${TL[py3]:-}" ]] && TL[py]="${TL[py3]}"
[[ -z "${TL[py]:-}" && -n "${TL[py2]:-}" ]] && TL[py]="${TL[py2]}"

[[ ! -n "${TL[$LANGUAGE]}" ]] && TL[$LANGUAGE]=${TL[default]}

if [[ -n "${TLMOD[$LANGUAGE.sum]}" ]]; then
  TL[$LANGUAGE]=$(echo "${TL[$LANGUAGE]}+${TLMOD[$LANGUAGE.sum]}"|bc -l)
fi
if [[ -n "${TLMOD[$LANGUAGE.mult]}" ]]; then
  TL[$LANGUAGE]=$(echo "${TL[$LANGUAGE]}*${TLMOD[$LANGUAGE.mult]}"|bc -l)
fi

if [[ ! -n "${TLMOD[$LANGUAGE.drift]}" ]]; then
  TLMOD[$LANGUAGE.drift]=0
fi

ETL=$(echo 2+${TL[$LANGUAGE]}+0.2+${TLMOD[$LANGUAGE.drift]}*2|bc -l)
RESP=""
RESPERRO=0
CORRECT=0
TOTALTESTS=$(ls -d $PROBLEMTEMPLATEDIR/tests/input/*|wc -l)

function run-testinput()
{
  local INPUT=$1
  local FILE=$(basename $INPUT)
  bash cage-run.sh $CAGEROOTARG $EXTRABINDINGS -d $workdir -i $INPUT -o $workdirbase/$FILE-team_output \
       -s $workdirbase/$FILE-stderr $SHIELDPARAMS\
       -r $LANGRUN \
       -t $workdirbase/$FILE-log.timelog\
       -T $ETL\
       -B $workdirbase/$FILE-log.bwraptime &> $workdirbase/$FILE-log.cage-run
  local BWRAPEXITCODE=$?
  echo $BWRAPEXITCODE > $workdirbase/$FILE-log.bwrapexitcode
  local EXECTIME=$(grep '^real' $workdirbase/$FILE-log.timelog|awk '{print $NF}')
  local ERR=0
  local VERDICT=""
  if echo "($EXECTIME - ${TL[$LANGUAGE]}) > ${TLMOD[$LANGUAGE.drift]} "|bc -l |grep -q 1; then
    VERDICT=TLE
    ERR=3
  elif (( BWRAPEXITCODE >= 127 )) ; then
    VERDICT=RE
    ERR=127
  elif (( BWRAPEXITCODE != 0 )) ; then
    VERDICT=RE_NZEC
    ERR=126
  else
    $LANGCOMPARE $workdirbase/$FILE-team_output $PROBLEMTEMPLATEDIR/tests/output/$FILE $INPUT &> $workdirbase/$FILE-log.compare
    COMPAREEXIT=$?
    if (( COMPAREEXIT == 4 )); then
      VERDICT=AC
      ERR=0
    elif (( COMPAREEXIT == 5 )); then
      VERDICT=AC,PE
      ERR=0
    elif (( COMPAREEXIT == 6 )); then
      VERDICT=WA
      ERR=6
    else
      VERDICT=UE
      ERR=7
    fi
  fi
  # limite de memória por RSS medido (res %M) — só se MEMLIMITMB no conf e o teste rodou.
  if [[ -n "${MEMLIMITMB:-}" && "$VERDICT" != TLE && "$VERDICT" != RE && "$VERDICT" != RE_NZEC ]]; then
    local RSSKB=$(grep '^res' $workdirbase/$FILE-log.timelog 2>/dev/null|awk '{print $NF}')
    if [[ "$RSSKB" =~ ^[0-9]+$ ]] && (( RSSKB > MEMLIMITMB*1024 )); then VERDICT=MLE; ERR=9; fi
  fi
  echo "VERDICT[$FILE]=$VERDICT" >> $workdirbase/log.verdictall
  echo "$VERDICT" > $workdirbase/$FILE-log.verdict
  return $ERR
}

JOBSCOUNT=0
NPROC=$(nproc)
[[ "$ALLOWPARALLELTEST" == "n" ]] && NPROC=1 && LOG " - Parallel Test not allowed in this problem"
[[ -n "$MAXPARALLELTESTS" ]] && NPROC=$MAXPARALLELTESTS && LOG " - Setting MAX Parallel Tests to $MAXPARALLELTESTS"
LOG " - NPROC: $NPROC"
for INPUT in $PROBLEMTEMPLATEDIR/tests/input/*; do
  if [[ ! -e "$INPUT" ]]; then
    echo "Wrong package format. No input found"
    LOG "$INPUT not found"
    exit 3
  fi
  run-testinput $INPUT &
  ((JOBSCOUNT++))
  if (( JOBSCOUNT > NPROC-1 )); then
    wait -n
    RET=$?
    (( RET == 6 )) && [[ "$STOPWHEN_WA" == "y" ]] && break
    (( RET == 3 )) && [[ "$STOPWHEN_TLE" == "y" ]] && break
    (( RET >= 126 )) && [[ "$STOPWHEN_RE" == "y" ]] && break
    (( RET != 0 )) && [[ "$RUNALL" != "y" ]] && break
    ((JOBSCOUNT--))
  fi
done

wait

TLERERUN=${TLERERUN:=y}

declare -A VERDICT
[[ -e $workdirbase/log.verdictall ]] && source $workdirbase/log.verdictall

declare -A VERDICTORDER
VERDICTORDER[UE]=6
VERDICTORDER[MLE]=5
VERDICTORDER[TLE]=5
VERDICTORDER[RE]=4
VERDICTORDER[RE_NZEC]=4
VERDICTORDER[TMT]=3
VERDICTORDER[WA]=2
VERDICTORDER[AC]=1
VERDICTORDER[AC,PE]=1
SMALLRESP=AC

for INPUT in $PROBLEMTEMPLATEDIR/tests/input/*; do
  LOG "--------------------------------------------------------------------"
  if [[ ! -e "$INPUT" ]]; then
    echo "Wrong package format. No input found"
    LOG "$INPUT not found"
    exit 3
  fi
  FILE=$(basename $INPUT)
  LOG ""
  LOG "## Testfile: $FILE"
  LOG ""
  THISRERUN=0
  THISVERDICT=${VERDICT[$FILE]}
  [[ -z "$THISVERDICT" ]] &&
    LOG " - Can't find VERDICT for this FILE($INPUT)" &&
    RESP="INPUT NOT TESTED" && ((RESPERRO++)) && continue

  if [[ "$THISVERDICT" == "TLE" ]]; then
    if [[ "$TLERERUN" == "y" ]]; then
	    LOG " - Rerun: because got TLE while running parallel tests"
	    run-testinput $INPUT
	    THISRERUN=1
      source $workdirbase/log.verdictall
      THISVERDICT="${VERDICT[$FILE]}"
      [[ "$THISVERDICT" == "TLE" ]] && TLERERUN=n
    else
	    LOG " - Rerun: It will not be RERUNNED because previous RERUN were TLE"
    fi
  fi

  LOG ""
  LOG "### CAGE CONTROL DATA this is for Bruno to check"
  LOG "8<-------------------------8<------------------"
  for f in $workdirbase/$FILE-{stderr,log.cage-run,log.timelog,log.bwraptime,log.bwrapexitcode}; do
    wc -c "$f"|grep -q "^0 " && continue;
    [[ "$f" == "$workdirbase/$FILE-team_output" ]] && continue
    LOG "#### $(basename $f)"
    LOG "$(< $f)"
  done
  LOG "8<-------------------------8<------------------"
  LOG "### END CAGE CONTROL DATA"
  LOG ""
  LOG ""

  EXECTIME=$(grep '^real' $workdirbase/$FILE-log.timelog|awk '{print $NF}')
  LOG "EXECTIME $FILE $EXECTIME $THISVERDICT"
  LOG " - Execution Time: $EXECTIME"
  LOG " - Time Limit for this problem is: ${TL[$LANGUAGE]}"
  LOG " - Verdict for this output: $THISVERDICT"
  LOG ""

  [[ "$THISVERDICT" =~ "AC" ]] || ((RESPERRO++))
  [[ "$THISVERDICT" =~ "AC" ]] && ((CORRECT++))

  LOG "### CHECKING SOLUTION THIS IS USUALLY A DIFF OUTPUT"

  ((RESPERRO > 2 )) && [[ "$THISVERDICT" != "AC" ]] && [[ "$THISVERDICT" != "AC,PE" ]] && LOG " - Will NOT show DIFFS or Courtesy for MORE than 2 errors"
  ((RESPERRO <= 2 )) && [[ "$THISVERDICT" != "AC" ]] && [[ "$THISVERDICT" != "TMT" ]] && [[ "$THISVERDICT" != "TLE" ]] && [[ "$THISVERDICT" != "RE" ]] && LOG "$(< $workdirbase/$FILE-log.compare)"
  ((RESPERRO <= 2 )) && [[ "$THISVERDICT" != "AC,PE" ]] && [[ "$THISVERDICT" != "AC" ]] && [[ "$INPUT" =~ "sample" || "$INPUT" =~ "example" ]] && LOG "" && LOG "#### INPUT COURTESY [this is the raw input file]" && LOG "\`\`\`" && LOG "$(< $INPUT)" && LOG "\`\`\`" && LOG ""
  LOG ""
  ##ORDEM PIOR PARA MELHOR UE -> TLE -> RE -> TMT -> WA -> AC
  #LOG "SMALLRESP=$SMALLRESP"
  #LOG "THISVERDICT=$THISVERDICT"
  #LOG "${VERDICTORDER[$SMALLRESP]} , ${VERDICTORDER[$THISVERDICT]}"
  (( ${VERDICTORDER[$SMALLRESP]} < ${VERDICTORDER[$THISVERDICT]} )) && SMALLRESP=$THISVERDICT
done

[[ "$SMALLRESP" =~ "AC" ]] && (( RESPERRO > 0 )) && SMALLRESP=UE

declare -A VERDICTFULLNAME
VERDICTFULLNAME[UE]="Unknown ERROR"
VERDICTFULLNAME[MLE]="Memory Limit Exceeded"
VERDICTFULLNAME[TLE]="Time Limit Exceeded"
VERDICTFULLNAME[RE]="Runtime Error"
VERDICTFULLNAME[RE_NZEC]="Possible Runtime Error, non-zero return"
VERDICTFULLNAME[TMT]="Runtime Error, signaled PPDI"
VERDICTFULLNAME[WA]="Wrong Answer"
VERDICTFULLNAME[AC]="Accepted"
VERDICTFULLNAME[AC,PE]="Accepted,PE"
((TOTALTIME=EPOCHSECONDS-STARTTIME))
LOG ""
LOG ""
LOG "# FINAL VERDICT"
LOG "  - Total build-and-test time: $TOTALTIME seconds"
LOG "  - $SMALLRESP - ${VERDICTFULLNAME[$SMALLRESP]}"
LOG "  - $CORRECT correct in $TOTALTESTS , $((CORRECT*100/TOTALTESTS))%"

FINALRESP="${VERDICTFULLNAME[$SMALLRESP]},$((CORRECT*100/TOTALTESTS))p"

# Veredicto CANÔNICO (sem score) + score estruturado, p/ o backend casar o auto-veredicto e o
# treino montar o resumo. O mapa colapsa variações de erro nos rótulos do vocabulário oficial.
declare -A VERDICTCANON=(
  [AC]="Accepted" [AC,PE]="Accepted" [WA]="Wrong Answer" [TLE]="Time Limit Exceeded"
  [MLE]="Memory Limit Exceeded" [RE]="Runtime Error" [RE_NZEC]="Runtime Error"
  [TMT]="Runtime Error" [UE]="Runtime Error" [CE]="Compilation Error" )
VERDICT_CANON="${VERDICTCANON[$SMALLRESP]:-${VERDICTFULLNAME[$SMALLRESP]}}"
SCORE=$(( TOTALTESTS>0 ? CORRECT*100/TOTALTESTS : 0 )); SCORE_MAX=100; SCORE_KIND=tests
SCORE_GROUPS=""

# Pontuação por grupos (subtasks): se o problema traz um scripts/summary.sh próprio,
# usa o dele (compat com os problemas OBI legados); senão, se há tests/score, usa o
# scorer canônico genérico. Qualquer um sobrescreve FINALRESP com a soma dos grupos.
SUMMARY=$PROBLEMTEMPLATEDIR/scripts/summary.sh
if [[ -e "$SUMMARY" ]]; then
  source "$SUMMARY"
elif [[ -e "$PROBLEMTEMPLATEDIR/tests/score" ]]; then
  source "$SELFDIR/score-summary.sh"
fi

gen_report normal

echo $FINALRESP
exit 0
