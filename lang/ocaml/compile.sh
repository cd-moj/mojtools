#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.ml)
MLFLAGS=-O3

all: $(patsubst %.ml,%,${SRC})

%: %.ml
	@ocamlopt -O3 ${CXXFLAGS} $^ -o $@
	@echo BIN=$@
EOF

unset MAKELEVEL
make
