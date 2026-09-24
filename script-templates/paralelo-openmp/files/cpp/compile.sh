#!/bin/bash
# scripts/cpp/compile.sh — OpenMP: igual ao lang/cpp/compile.sh do mojtools, com -fopenmp.
# Roda DENTRO da jaula (cópia real, não stub). Não precisa de nada no run.sh: a jaula já entra
# com OMP_NUM_THREADS = CPUNEEDED (binfile.sh). Guia: mojtools/docs/problema-paralelo.md

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOM'

SRC=$(wildcard *.cpp)
CXXFLAGS=-O2 -fopenmp -static -std=gnu++20 -pipe

all: $(patsubst %.cpp,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU.
%: %.cpp
	@g++ ${CXXFLAGS} '$^' -o '$@' -lm
	@echo "BIN=$@"
EOM

unset MAKELEVEL
make
