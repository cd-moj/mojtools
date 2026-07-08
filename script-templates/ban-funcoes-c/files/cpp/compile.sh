#!/bin/bash
# Ban de funções em C++: se a fonte usa alguma função proibida, vira Compilation Error.
# EDITE a lista BANNED (nomes separados por |, sem espaços).
BANNED='strlen|strcpy|strncpy|strcmp|strncmp|strcat|strncat|strchr|strrchr|strstr|strtok|strdup'

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

if grep -qE "(^|[^[:alnum:]_])($BANNED)[[:space:]]*\(" *.cpp; then
  echo "Uso de função proibida detectado ($BANNED) — implemente manualmente." >&2
  exit 1
fi

cat > Makefile << 'MAKEEOF'
SRC=$(wildcard *.cpp)
CFLAGS=-lm -O2 -static
all: $(patsubst %.cpp,%,${SRC})
%: %.cpp
	@g++ ${CFLAGS} -std=gnu++20 $^ -o $@ -lm
	@echo BIN=$@
MAKEEOF
unset MAKELEVEL
make
