#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

exec dyalogscript ./$BIN < /tmp/in > /tmp/out
