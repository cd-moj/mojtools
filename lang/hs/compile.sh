#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.hs)
HSFLAGS=

all: $(patsubst %.hs,%,${SRC})

%: %.hs
	@ghc ${HSFLAGS} $^ -o $@
	@echo BIN=$@
EOF

unset MAKELEVEL
make
