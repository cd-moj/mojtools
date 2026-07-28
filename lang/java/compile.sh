#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

export _JAVA_OPTIONS="-Xmx300M -Xms50M -Xss10M"
javac *java
RET=$?
#java -Xms10m -Xmx500m -Xss10m

# BIN = a classe que tem o main. NUNCA `ls *.class`: com classe aninhada ou lambda o javac
# gera `Main$X.class`, e na collation C o '$' (0x24) vem ANTES do '.' (0x2E) — o `ls` devolvia
# "Main$X.class Main.class", o build-and-test pegava o PRIMEIRO e o run.sh tentava rodar a
# classe interna ("main method not found"), de forma dependente de locale. Elege pelo FONTE
# que declara main; senão Main.class; em último caso o 1º .class SEM '$' (nunca uma interna).
CLS=""
for f in $(grep -l -E 'static[[:space:]]+(final[[:space:]]+)?void[[:space:]]+main[[:space:]]*\(' *.java 2>/dev/null); do
  b="${f%.java}"
  [[ -f "$b.class" ]] && { CLS="$b.class"; break; }
done
[[ -z "$CLS" && -f Main.class ]] && CLS=Main.class
if [[ -z "$CLS" ]]; then
  for c in *.class; do [[ "$c" == *'$'* ]] && continue; [[ -f "$c" ]] || continue; CLS="$c"; break; done
fi

echo BIN=$CLS
exit $RET
