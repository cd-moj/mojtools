#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.go)
GOFLAGS=-lm -O2 -static

all: $(patsubst %.go,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU (ver cpp).
%: %.go
	@gccgo ${GOFLAGS} '$^' -o '$@' -lm
	@echo "BIN=$@"
EOF

unset MAKELEVEL
make
