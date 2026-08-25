#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.hs)
HSFLAGS=

all: $(patsubst %.hs,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU (ver cpp).
%: %.hs
	@ghc ${HSFLAGS} '$^' -o '$@' >&2
	@echo "BIN=$@"
EOF

unset MAKELEVEL
make
