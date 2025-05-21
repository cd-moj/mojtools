#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

exec prolog -s ./$BIN -g "main" -t halt < /tmp/in > /tmp/out
