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
  rm $TEMP
  rm -rf $TOREMOVE
}

trap sai EXIT


PROBLEMDIR=$(realpath $1)

cd $(dirname $0)

if [[ ! -e build-and-test.sh ]]; then
  stat build-and-test.sh
  exit 1
fi

#create dummy TL file, must be remove later
echo 'TL[default]=600' > $PROBLEMDIR/tl

declare -A ULIMITS TLMOD
[[ -e $PROBLEMDIR/conf ]] && source $PROBLEMDIR/conf

# find -ac solutions
WORSTTIME=0.01
declare -A WORSTTIMEPERLANG

for AC in $PROBLEMDIR/sols/good/*; do
  echo "${AC##*/}:"
  LANG=${AC##*.}
  [[ ! -n "${WORSTTIMEPERLANG[$LANG]}" ]] && WORSTTIMEPERLANG[$LANG]=0.01

  readarray -t T <<< $(bash build-and-test.sh ${AC##*.} $AC $PROBLEMDIR)
  if [[ "${T[1]}" == "Accepted" ]]; then
    grep '^EXECTIME' ${T[0]}/build-and-test.log > $TEMP
    while read l l ET SMALLRESP; do
      printf "$ET "
      if echo "$ET > ${WORSTTIMEPERLANG[$LANG]}"|bc |grep -q 1; then
        WORSTTIMEPERLANG[$LANG]=$ET
      fi
    done < $TEMP
    echo

  else
    echo "$AC got '${T[1]}', was waiting Accepted. Check ${T[0]}"
    exit 1
  fi
  TOREMOVE+=" ${T[0]}"
done

TLMULT=1.35

[[ -n "${TLMOD[calibrafactor]}" ]] && TLMULT=${TLMOD[calibrafactor]}

BESTTIME=10000

rm $PROBLEMDIR/tl
echo "#Generated by calibreitor" > $PROBLEMDIR/tl

for t in ${!WORSTTIMEPERLANG[@]}; do

  WORSTTIMEPERLANG[$t]="$(echo "$TLMULT * ${WORSTTIMEPERLANG[$t]} + 0.02"|bc -l)"
  echo "TL[$t]=${WORSTTIMEPERLANG[$t]}" >> $PROBLEMDIR/tl
  if echo "${WORSTTIMEPERLANG[$t]} < $BESTTIME"|bc|grep -q 1; then
    BESTTIME=${WORSTTIMEPERLANG[$t]}
  fi
done

echo "TL[default]=$BESTTIME" >> $PROBLEMDIR/tl

cat $PROBLEMDIR/tl
echo

for TLs in $PROBLEMDIR/sols/slow/*; do
  if [[ ! -e $TLs ]]; then echo none; continue;fi
  echo "${TLs##*/}:"
  LANG="${TLs##*.}"
  readarray -t T <<< $(bash build-and-test.sh ${TLs##*.} $TLs $PROBLEMDIR runnall)
  grep '^EXECTIME' ${T[0]}/build-and-test.log > $TEMP
  while read l l ET SMALLRESP; do
    printf "$ET($SMALLRESP) "
  done < $TEMP
  echo
  TOREMOVE+=" ${T[0]}"
done
