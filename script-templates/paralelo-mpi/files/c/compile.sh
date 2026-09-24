#!/bin/bash
# scripts/c/compile.sh — MPI: mpicc (OpenMPI da rootfs; sem -static — a OpenMPI não linka
# estático). Roda DENTRO da jaula (cópia real). Guia: mojtools/docs/problema-paralelo.md

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOM'

SRC=$(wildcard *.c)
CFLAGS=-O2

all: $(patsubst %.c,%,${SRC})

# ASPAS: o nome do arquivo vem do ALUNO e o make entrega o recipe ao /bin/sh CRU.
%: %.c
	@mpicc ${CFLAGS} '$^' -o '$@' -lm
	@echo "BIN=$@"
EOM

unset MAKELEVEL
make
