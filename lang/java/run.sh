#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

export CLASSPATH=$PWD
exec java -Xms10m -Xmx500m -Xss10m $(basename $BIN .class) < /tmp/in > /tmp/out
