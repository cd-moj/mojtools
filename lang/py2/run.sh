#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

python ./$BIN < /tmp/in > /tmp/out
