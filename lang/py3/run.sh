#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

exec python3 ./$BIN < /tmp/in > /tmp/out
