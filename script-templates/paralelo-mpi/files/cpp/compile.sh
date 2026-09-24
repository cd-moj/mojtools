#!/bin/bash
# scripts/cpp/compile.sh — MPI: mpicxx (OpenMPI da rootfs; sem -static — a OpenMPI não linka
# estático). Roda DENTRO da jaula (cópia real). Guia: mojtools/docs/problema-paralelo.md

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOM'

SRC=$(wildcard *.cpp)
CXXFLAGS=-O2 -std=gnu++20 -pipe

all: $(patsubst %.cpp,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU.
%: %.cpp
	@mpicxx ${CXXFLAGS} '$^' -o '$@' -lm
	@echo "BIN=$@"
EOM

unset MAKELEVEL
make
