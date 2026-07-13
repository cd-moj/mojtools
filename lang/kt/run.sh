#!/bin/bash

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh

# heap = MEMLIMITMB do problema (via binfile.sh; 500m sem limite definido); -Xss espelha o
# stack do problema (threads da JVM não obedecem o ulimit -s da thread main)
exec java -Xms10m -Xmx${MOJ_MEMLIMITMB:-500}m -Xss${MOJ_STACKKB:-131072}k -jar "$BIN" < /tmp/in > /tmp/out
