#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.c)
CFLAGS=-lm -O2 -static

all: $(patsubst %.c,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU (ver cpp).
%: %.c
	@gcc ${CFLAGS} '$^' -o '$@' -lm
	@echo "BIN=$@"
EOF

unset MAKELEVEL
make
