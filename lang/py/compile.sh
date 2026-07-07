#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

chmod a+x *py* 2>/dev/null
# BIN antes do py_compile: o __pycache__ criado poluiria o ls
BINF=$(ls *.py *.py3 *.py2 2>/dev/null | head -1)
[[ -n "$BINF" ]] || exit 1
# pypy3 quando existe (rootfs do juiz); CPython no modo host/dev
PY=python3; command -v pypy3 >/dev/null 2>&1 && PY=pypy3
# check de sintaxe: erro -> traceback no stderrlog, sem BIN= -> Compilation Error
$PY -m py_compile "$BINF" || exit 1
echo BIN=$BINF
