#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.pas)

all: $(patsubst %.pas,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU (ver cpp).
# O `-o` do fpc é GRUDADO no valor: `-o'$@'`, não `-o '$@'`.
%: %.pas
	@fpc -o'$@' '$^' -TLINUX >&2
	@echo "BIN=$@"
EOF

unset MAKELEVEL
make
