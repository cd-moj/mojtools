#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.ml)

all: $(patsubst %.ml,%,${SRC})

%: %.ml
	@ocamlopt -O3 $^ -o $@
	@echo BIN=$@
EOF

unset MAKELEVEL
make
