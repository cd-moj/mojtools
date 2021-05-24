#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.rs)

all: $(patsubst %.rs,%,${SRC})

%: %.rs
	@rustc -C opt-level=3 $^ -o $@
	@echo BIN=$@
EOF

unset MAKELEVEL
make
