#!/bin/bash

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh

# heap = MEMLIMITMB do problema (via binfile.sh; 500m sem limite definido); -Xss espelha o
# stack do problema (threads da JVM não obedecem o ulimit -s da thread main). Locale e charset
# fixos pelas razões do lang/java/run.sh (o kotlinc já lê o fonte em UTF-8: não precisa de flag).
exec java -Duser.language=en -Duser.country=US -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 \
     -Xms10m -Xmx${MOJ_MEMLIMITMB:-500}m -Xss${MOJ_STACKKB:-131072}k -jar "$BIN" < /tmp/in > /tmp/out
