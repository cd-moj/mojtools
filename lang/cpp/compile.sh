#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'

SRC=$(wildcard *.cpp)
CXXFLAGS=-lm -O2 -static -std=gnu++20 -pipe

all: $(patsubst %.cpp,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU. Um
# `l(1).cpp` — a marca que o navegador gruda em download repetido — virava
# `g++ … l(1).cpp -o l` e dava erro de sintaxe do sh = Compilation Error (relato de time).
%: %.cpp
	@g++ ${CXXFLAGS} '$^' -o '$@' -lm
	@echo "BIN=$@"
EOF

unset MAKELEVEL
make
