#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.cs)

all: $(patsubst %.cs,%,${SRC})

%: %.cs
	@mcs -optimize $^ -o $@
	@echo BIN=$@
EOF

ls /etc/mono >&2
unset MAKELEVEL
make
