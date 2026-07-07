#!/bin/bash

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh

# pypy3 explícito (desempenho) com fallback p/ o python3 do ambiente (modo host/dev)
command -v pypy3 >/dev/null 2>&1 && exec pypy3 ./$BIN < /tmp/in > /tmp/out
exec python3 ./$BIN < /tmp/in > /tmp/out
