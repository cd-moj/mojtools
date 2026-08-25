#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.cs)

all: $(patsubst %.cs,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU (ver cpp).
%: %.cs
	@mcs -optimize '$^' -out:'$@'
	@echo "BIN=$@"
EOF

ls /etc/mono >&2
unset MAKELEVEL
make
