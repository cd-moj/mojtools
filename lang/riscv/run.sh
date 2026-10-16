#!/bin/bash

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

# `nc` = sem o banner de copyright; `me` = as mensagens do simulador (fim do programa, erro de execução) vão p/ o
# stderr. Assim o stdout é SÓ o que o programa imprimiu. Antes a saída era recortada por linha (`tail -n+3 | head -n-2`,
# banner + rodapé "Program terminated…"), o que (1) comia a última linha de quem não termina a saída com quebra de
# linha (WA) e (2) com o RARS 1.6 comia as 2 últimas linhas de TODO programa que imprime: o 1.6 fecha o System.out no
# primeiro print e o rodapé nunca sai (rars#199). `exit 0`: o código de saída do programa não vira RE — como no recorte
# antigo, em que quem saía era o `head`.
java -jar rars.jar nc me "$BIN" < /tmp/in > /tmp/out
exit 0

