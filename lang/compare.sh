#!/bin/bash
# ////////////////////////////////////////////////////////////////////////////////
# //BOCA Online Contest Administrator
# //    Copyright (C) 2003-2012 by BOCA Development Team (bocasystem@gmail.com)
# //
# //    This program is free software: you can redistribute it and/or modify
# //    it under the terms of the GNU General Public License as published by
# //    the Free Software Foundation, either version 3 of the License, or
# //    (at your option) any later version.
# //
# //    This program is distributed in the hope that it will be useful,
# //    but WITHOUT ANY WARRANTY; without even the implied warranty of
# //    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# //    GNU General Public License for more details.
# //    You should have received a copy of the GNU General Public License
# //    along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ////////////////////////////////////////////////////////////////////////////////
# // Last modified 21/jul/2012 by cassio@ime.usp.br
#
# This script receives:
# $1 team_output
# $2 sol_output
# $3 problem_input (might be used by some specific checkers, here it is not)
#
# BOCA reads the last line of the standard output
# and pass it to judges
#
if [ ! -r "$1" -o ! -r "$2" ]; then
  echo "Parameter problem"
  exit 43
fi

# Next lines of this script just compares team_output and sol_output,
# although it is possible to change them to more complex evaluations.

diff -q "$1" "$2" >/dev/null 2>/dev/null
if [ "$?" == "0" ]; then
  echo -e "diff \"$1\" \"$2\" # files match"
  echo "Files match exactly"
  exit 4
fi
diff -q -b "$1" "$2" >/dev/null 2>/dev/null
if [ "$?" == "0" ]; then
  echo -e "diff -c -b \"$1\" \"$2\" # files match"
  echo -e "diff -c \"$1\" \"$2\" # files dont match - see output"
  diff -c "$1" "$2"
  echo "Files match with differences in the amount of white spaces"
  exit 5
fi
diff -q -b -B "$1" "$2" >/dev/null 2>/dev/null
if [ "$?" == "0" ]; then
  echo -e "diff -c -b -B \"$1\" \"$2\" # files match"
  echo -e "diff -c -b \"$1\" \"$2\" # files dont match - see output"
  diff -c -b "$1" "$2"
  echo "Files match with differences in the amount of white spaces and blank lines"
  exit 5
fi
diff -q -i -b -B "$1" "$2" >/dev/null 2>/dev/null
if [ "$?" == "0" ]; then
  echo -e "diff -c -i -b -B \"$1\" \"$2\" # files match"
  echo -e "diff -c -b -B \"$1\" \"$2\" # files dont match - see output"
  diff -c -b -B "$1" "$2"
  echo "Files match if we ignore case and differences in the amount of white spaces and blank lines"
  exit 5
fi
diff -q -b -B -w "$1" "$2" >/dev/null 2>/dev/null
if [ "$?" == "0" ]; then
  echo -e "diff -c -b -B -w \"$1\" \"$2\" # files match"
  echo -e "diff -c -i -b -B \"$1\" \"$2\" # files dont match - see output"
  diff -c -i -b -B "$1" "$2"
  echo "Files match if we discard all white spaces"
  exit 5
fi
diff -q -i -b -B -w "$1" "$2" >/dev/null 2>/dev/null
if [ "$?" == "0" ]; then
  echo -e "diff -c -i -b -B -w \"$1\" \"$2\" # files match"
  echo -e "diff -c -b -B -w \"$1\" \"$2\" # files dont match - see output"
  diff -c -b -B -w "$1" "$2"
  echo "Files match if we ignore case and discard all white spaces"
  exit 5
fi
wd=`which wdiff`
if [ "$wd" != "" ]; then
  wdiff \"$1\" \"$2\" >/dev/null 2>/dev/null
  if [ "$?" == "0" ]; then
    echo -e "wdiff \"$1\" \"$2\" # files match"
    echo -e "diff -u -i -b -B -w \"$1\" \"$2\" # files dont match - see output"
    diff -u -i -b -B -w "$1" "$2"
    echo "BUT Files match if we compare word by word, ignoring everything else, using wdiff"
    echo "diff has a bug that, if a line contains a single space, this is not discarded by -w"
    exit 5
  fi
fi
echo -e "### files dont match - see output"
diff -u -i -b -B -w "$1" "$2"
echo "Differences found"
exit 6
