#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.rs)

all: $(patsubst %.rs,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU (ver cpp).
%: %.rs
	@rustc -C opt-level=3 '$^' -o '$@'
	@echo "BIN=$@"
EOF

unset MAKELEVEL
make
