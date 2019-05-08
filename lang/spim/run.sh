#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

spim -file $BIN < /tmp/in |tail -n+6 > /tmp/out
