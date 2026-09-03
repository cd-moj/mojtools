#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

export CLASSPATH=$PWD
# -Duser.language=en -Duser.country=US: Scanner.nextDouble()/printf(%f) sao sensiveis ao locale
# do SISTEMA, que a rootfs as vezes nao tem de fato instalado (LANG pede pt_BR.UTF-8 sem o
# locale gerado) -- vira inconsistente entre execucoes: as vezes cai em formato C (ponto), as
# vezes fica num meio-termo quebrado (virgula na saida, ponto esperado na entrada ->
# InputMismatchException). Forcar en_US torna deterministico p/ QUALQUER solucao Java que
# leia/imprima ponto flutuante, independente do locale instalado no host.
# -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8: mesma causa raiz (locale ausente no host) do
# lado do CHARSET -- sem isso o System.out cai p/ um encoding que nao e UTF-8 e acentos viram
# "?" (Media -> M?dia). So nao apareceu nos problemas cuja saida de referencia e so ASCII.
# heap = MEMLIMITMB do problema (via binfile.sh; 500m sem limite definido); -Xss espelha o
# stack do problema (threads da JVM não obedecem o ulimit -s da thread main)
exec java -Duser.language=en -Duser.country=US -Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 \
     -Xms10m -Xmx${MOJ_MEMLIMITMB:-500}m -Xss${MOJ_STACKKB:-131072}k "$(basename "$BIN" .class)" < /tmp/in > /tmp/out
