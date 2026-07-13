#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

# kotlinc empacota o runtime no jar (-include-runtime) e aponta o Main-Class do
# `fun main()` do fonte no manifest — o run.sh só precisa de `java -jar`.
export JAVA_OPTS="-Xmx700M -Xms64M"
kotlinc *.kt -include-runtime -d prog.jar
RET=$?

echo BIN=prog.jar
exit $RET
