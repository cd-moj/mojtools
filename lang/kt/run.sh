#!/bin/bash

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh

exec java -Xms10m -Xmx500m -Xss10m -jar "$BIN" < /tmp/in > /tmp/out
