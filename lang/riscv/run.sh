#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

java -jar rars.jar $BIN |tail -n+3|head -n-2 > /tmp/out

