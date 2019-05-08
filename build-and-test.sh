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
  echo "$0 <LANGUAGE> <SRCFILE> <PROBLEMTEMPLATEDIR> <RUNALL?yes:no>"
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

mkdir -p $workdir
echo $workdirbase

cp "$SRCCODE" $workdir/

declare -a BIN

declare -A ULIMITS
declare -A TLMOD

DEFAULTSHIELDCPU=3
DEFAULTSHIELDUSER=judge

#set default values
#configurações de variáveis do ulimit
## stack
### default to 200MB
ULIMITS[-s]=204800

## file size
### default to 100MB
ULIMITS[-f]=25600

## virtual memory
### default to 600MB
#ULIMITS[-v]=614400

## max processes
### default to 1024
ULIMITS[-u]=1024

#check if there is conf
[[ -e $PROBLEMTEMPLATEDIR/conf ]] && source $PROBLEMTEMPLATEDIR/conf

#set ulimits
for l in ${!ULIMITS[@]}; do
  ulimit $l ${ULIMITS[$l]}
  LOG "set: ulimit $l ${ULIMITS[$l]}"
done

#default locations
LANGUAGEDIR=$(dirname $0)/lang/$LANGUAGE
LANGUAGEDIR=$(realpath $LANGUAGEDIR)
#LANGCOMPILE=$(realpath $LANGCOMPILE)

# check for other source of compile
[[ -d "$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE/" ]] && LANGUAGEDIR="$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE"

LANGCOMPILE=$LANGUAGEDIR/compile.sh

if [[ ! -e "$LANGCOMPILE" ]]; then
  echo "Language '$LANGUAGE' not availale"
  LOG "$LANGCOMPILE not found"
  exit 3
fi

[[ -x $LANGUAGEDIR/prep.sh ]] && $LANGUAGEDIR/prep.sh $workdir

if [[ "$USER" == root ]]; then
  SHIELDPARAMS="--shield-cpu $DEFAULTSHIELDCPU --shield-user $DEFAULTSHIELDUSER"
fi

LOG "# Compiling"
bash cage-run.sh -w $workdir -r $LANGCOMPILE $SHIELDPARAMS\
                    -s $workdirbase/compile.log.stderr \
                    -o $workdirbase/compile.log.stdout \
                    -t $workdirbase/compile.log.time \
                    -T 30\
                    -B $workdirbase/compile.log.bwraptime &> $workdirbase/compile.log.cage-run

CAGERET=$?

if ! grep -q ^BIN= $workdirbase/compile.log.stdout || (( CAGERET != 0 )) ; then
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
LOG "# Running"

LANGRUN=$LANGUAGEDIR/run.sh
#LANGRUN=$(realpath $LANGRUN)

#[[ -e "$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE/run.sh" ]] && LANGRUN="$PROBLEMTEMPLATEDIR/scripts/$LANGUAGE/run.sh"

LANGCOMPARE=$LANGUAGEDIR/compare.sh
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

ETL=$(echo 2*${TL[$LANGUAGE]}+5|bc -l)
RESP=
RESPERRO=0

for INPUT in $PROBLEMTEMPLATEDIR/tests/input/*; do
  LOG "--------------------------------------------------------------------"
  if [[ ! -e "$INPUT" ]]; then
    echo "Wrong package format. No input found"
    LOG "$INPUT not found"
    exit 3
  fi
  FILE=$(basename $INPUT)
  LOG ""
  LOG "# $INPUT"
  LOG ""

  bash cage-run.sh -d $workdir -i $INPUT -o $workdirbase/$FILE-team_output \
                   -s $workdirbase/$FILE-stderr $SHIELDPARAMS\
                      -r $LANGRUN \
                      -t $workdirbase/$FILE-log.timelog\
                      -T $ETL\
                      -B $workdirbase/$FILE-log.bwraptime &> $workdirbase/$FILE-log.cage-run
  BWRAPEXITCODE=$?
  for f in $workdirbase/$FILE-{stderr,log.cage-run,log.timelog,log.bwraptime}; do
    [[ "$f" == "$workdirbase/$FILE-team_output" ]] && continue
    LOG "## $f"
    LOG "$(< $f)"
    LOG ""
  done
  $LANGCOMPARE $workdirbase/$FILE-team_output $PROBLEMTEMPLATEDIR/tests/output/$FILE &> $workdirbase/$FILE-log.compare
  COMPAREEXIT=$?
  LOG "## $FILE compare output"
  LOG "$(< $workdirbase/$FILE-log.compare)"
  LOG ""
  if (( COMPAREEXIT == 4 )); then
    if (( RESPERRO == 0 )); then
      RESP="Accepted"
      SMALLRESP=AC
    fi
  elif (( COMPAREEXIT == 5 )); then
    RESP="Presentation Error"
    SMALLRESP=PE
    ((RESPERRO++))
  elif (( COMPAREEXIT == 6 )); then
    RESP="Wrong Aswer"
    SMALLRESP=WA
    ((RESPERRO++))
  else
    RESP="Unknown Error"
    SMALLRESP=UE
    ((RESPERRO++))
  fi
  LOG "$FILE COMPARE $COMPAREEXIT"

  EXECTIME=$(grep '^real' $workdirbase/$FILE-log.timelog|awk '{print $NF}')
  if echo "($EXECTIME - ${TL[$LANGUAGE]}) > ${TLMOD[$LANGUAGE.drift]} "|bc -l |grep -q 1; then
    OLDRESP="$RESP"
    RESP="Time Limit Exceeded"
    SMALLRESP=TLE
    LOG "## $FILE TLE $EXECTIME > ${TL[$LANGUAGE]}"
    if (( COMPAREEXIT == 4 )); then
      LOG "### $FILE But it was finished with $OLDRESP"
    fi
  fi

  if (( BWRAPEXITCODE == 124 )) && [[ "$SMALLRESP" != "TLE" ]]; then
    RESP="Time Limit Exceeded"
    SMALLRESP=TMT
    ((RESPERRO++))
    [[ ! -n "$EXECTIME" ]] && EXECTIME="$(grep '^real' $workdirbase/$FILE-log.bwraptime|awk '{print $NF}')"
  elif (( BWRAPEXITCODE != 0 )) && [[ "$SMALLRESP" != "TLE" ]]; then
    RESP="Runtime Error"
    LOG "## $FILE Runtime Error"
    SMALLRESP=RE
    ((RESPERRO++))
  fi

  LOG "EXECTIME $FILE $EXECTIME $SMALLRESP"
  LOG
  [[ "$RESP" != "Accepted" ]] && [[ "$RESP" != "Presentation Error" ]] && [[ "$RUNALL" == "no" ]]  && break

done

echo "$RESP"
exit 0
