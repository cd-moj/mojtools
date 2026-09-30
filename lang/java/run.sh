#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

export CLASSPATH=$PWD
# Locale e charset FIXOS, independentes da rootfs do juiz. Sem eles a JVM segue o LANG da jaula, e
# o veredicto muda de um juiz para outro (é determinístico POR JUIZ, não por execução):
# - -Duser.language=en -Duser.country=US: num locale de vírgula decimal, Scanner.nextDouble() e
#   printf("%f") leem/escrevem "5,5" — InputMismatchException ou WA com a solução certa;
# - -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 (JDK 18+; antes é propriedade inerte): sem
#   locale UTF-8 o System.out troca acento por "?" ("Média" vira "M?dia").
# Os mesmos -D vão no lang/kt/run.sh e no _JVM do interactive/run.sh.
# heap = MEMLIMITMB do problema (via binfile.sh; 500m sem limite definido); -Xss espelha o
# stack do problema (threads da JVM não obedecem o ulimit -s da thread main)
exec java -Duser.language=en -Duser.country=US -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 \
     -Xms10m -Xmx${MOJ_MEMLIMITMB:-500}m -Xss${MOJ_STACKKB:-131072}k "$(basename "$BIN" .class)" < /tmp/in > /tmp/out
