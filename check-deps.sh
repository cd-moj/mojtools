#!/bin/bash

HARDDEPS='bash awk getopt /usr/bin/time timeout bwrap diff make bc'

SOFTDEPS='cset'

COMPILERS='gcc g++ fpc javac gccgo python2 python3 bash spim ocamlopt rustc node'

function checkdeps()
{
  local err=0
  for arg; do
    if ! which $arg &> /dev/null; then
      echo "$arg"
      ((err++))
    fi
  done
  return $err

}

echo "Checking HARDDEPS"
checkdeps $HARDDEPS && echo 'OK.'

echo
echo 'Checking SOFTDEPS'
checkdeps $SOFTDEPS && echo 'OK.'

echo
echo 'Checking Compilers/runtime'
checkdeps $COMPILERS && echo 'OK.'
