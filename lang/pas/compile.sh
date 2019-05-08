#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.pas)

all: $(patsubst %.pas,%,${SRC})

%: %.pas
	@fpc -o$@ $^ -TLINUX >&2
	@echo BIN=$@
EOF

unset MAKELEVEL
make
