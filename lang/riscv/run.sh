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
# `tr -d '\000'`: os bytes NUL saem da saída. O `write` (ecall 64) com tamanho MAIOR que a string imprime os zeros da
# memória que vêm depois dela — o "Olá Mundo" modelo dos cursos (e a solução do moj-problems#olamundo) escreve 13 bytes
# de "Ola Mundo\n": 3 NULs depois da linha. O recorte antigo os engolia por acaso (iam na linha do rodapé); sem ele
# viravam WA. NUL nunca é saída de texto válida, então descartá-lo não aceita resposta errada visível.
java -jar rars.jar nc me "$BIN" < /tmp/in | tr -d '\000' > /tmp/out
exit 0

