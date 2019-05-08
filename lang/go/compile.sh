#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.go)
GOFLAGS=-lm -O2 -static

all: $(patsubst %.go,%,${SRC})

%: %.go
	@gccgo ${GOFLAGS} $^ -o $@ -lm
	@echo BIN=$@
EOF

unset MAKELEVEL
make
