#!/bin/bash
# Driver de submissão-de-função (C++) — TEMPLATE. Igual ao de C (veja lá o racional e a
# SENTINELA anti-IO); aqui só muda o compilador e o arquivo. EDIT-ME: protótipo/leitura/
# chamada. Guia: mojtools/docs/submissao-de-funcao.md
cat > /tmp/rwdir/__judge_main.cpp <<'EOF'
#include <cstdio>

int soma(int a, int b);                      // EDIT-ME: protótipo da função do aluno

int main(){
  int n;
  if (scanf("%d", &n) != 1) return 0;
  for (int i = 0; i < n; i++) {
    int a, b;                                // EDIT-ME: leitura dos parâmetros
    if (scanf("%d %d", &a, &b) != 2) { printf("ENTRADA-CURTA\n"); return 0; }
    printf("%d\n", soma(a, b));              // EDIT-ME: chamada + impressão
  }
  int sentinela;                             // a funcao do aluno leu a entrada?
  if (scanf("%d", &sentinela) != 1 || sentinela != 424242) {
    printf("SENTINELA-VIOLADA (a funcao consumiu a entrada?)\n");
  }
  return 0;
}
EOF

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'
SRC=$(wildcard *.cpp)
CXXFLAGS=-lm -O2 -static -std=gnu++20

main: ${SRC}
	@g++ ${CXXFLAGS} $^ -o $@ -lm
	@echo BIN=$@
EOF

unset MAKELEVEL
make
