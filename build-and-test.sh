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

if [[ ! -n "$3" ]]; then
  echo "$0 <LANGUAGE> <SRCFILE> <PROBLEMTEMPLATEDIR> [<RUNALL?y:n>]"
  exit 1
fi

LANGUAGE=$1
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

exec 2> $workdirbase/build-and-test.log

LOG "% Running: $(basename $PROBLEMTEMPLATEDIR)"
LOG ""
LOG "- Minimal Information"
LOG "  - Submission Language: $LANGUAGE"
LOG "  - Submission SRCFILE: $(basename $SRCCODE)"
LOG "  - Run all even on critical error: $RUNALL"
LOG ""
LOG "- Starting at $(date -R)"
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

#set default values
#configurações de variáveis do ulimit
## stack
### default to 200MB
ULIMITS[-s]=204800

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

PREPLANGUAGE="$PROBLEMLANGUAGEDIR/prep.sh"
[[ -x "$PREPLANGUAGE" ]] && $PREPLANGUAGE $workdir
[[ ! -e "$PREPLANGUAGE" ]] && [[ -e "$DEFAULTLANGUAGEDIR/prep.sh" ]] &&
  $DEFAULTLANGUAGEDIR/prep.sh $workdir

if [[ "$USER" == root ]]; then
  SHIELDPARAMS="--shield-cpu $DEFAULTSHIELDCPU --shield-user $DEFAULTSHIELDUSER -M $DEFAULTMEMLIMIT"
fi

LOG "# Compiling code"
LOG ""
bash cage-run.sh -w $workdir -r $LANGCOMPILE $SHIELDPARAMS\
                    -s $workdirbase/compile.log.stderr \
                    -o $workdirbase/compile.log.stdout \
                    -t $workdirbase/compile.log.time \
                    -T 30\
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
  echo "Compilation Error"
  exit 1
fi
#cut -d'=' -f2 < $workdir/log.stdout
BIN+=( $(cut -d'=' -f2 < $workdirbase/compile.log.stdout) )
echo BIN=${BIN[0]} > $workdir/binfile.sh

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
if [[ ! -e "$PROBLEMTEMPLATEDIR/tl" ]]; then
  echo "Wrong package format. No TimeLimit found"
  LOG "Timelimit is not set"
  exit 3
fi
source $PROBLEMTEMPLATEDIR/tl

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
  bash cage-run.sh -d $workdir -i $INPUT -o $workdirbase/$FILE-team_output \
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
    ((ERR++))
  elif (( BWRAPEXITCODE >= 127 )) ; then
    VERDICT=RE
    ((ERR++))
  elif (( BWRAPEXITCODE != 0 )) ; then
    VERDICT=RE_NZEC
    ((ERR++))
  else
    $LANGCOMPARE $workdirbase/$FILE-team_output $PROBLEMTEMPLATEDIR/tests/output/$FILE $INPUT &> $workdirbase/$FILE-log.compare
    COMPAREEXIT=$?
    if (( COMPAREEXIT == 4 )); then
      VERDICT=AC
    elif (( COMPAREEXIT == 5 )); then
      VERDICT=AC,PE
    elif (( COMPAREEXIT == 6 )); then
      VERDICT=WA
      ((ERR++))
    else
      VERDICT=UE
      ((ERR++))
    fi
  fi
  echo "VERDICT[$FILE]=$VERDICT" >> $workdirbase/log.verdictall
  echo "$VERDICT" > $workdirbase/$FILE-log.verdict
  return $ERR
}

JOBSCOUNT=0
NPROC=$(nproc)
[[ "$ALLOWPARALLELTEST" == "n" ]] && NPROC=1 && LOG " - Parallel Test not allowed in this problem"
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

SUMMARY=$PROBLEMTEMPLATEDIR/scripts/summary.sh

[[ -e "$SUMMARY" ]] && source $SUMMARY

echo $FINALRESP
exit 0
