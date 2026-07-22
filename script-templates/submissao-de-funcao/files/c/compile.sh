#!/bin/bash
# Driver de submissão-de-função (C) — TEMPLATE. O aluno envia SÓ a(s) função(ões); este
# main lê a entrada, chama a função e imprime. Exemplo funcional: int soma(int a, int b).
# EDIT-ME: o protótipo, a leitura e a chamada. Guia: mojtools/docs/submissao-de-funcao.md
#
# SENTINELA anti-IO (não remova): a ÚLTIMA linha de TODO tests/input/* é `424242`.
# Depois de processar os casos, o main lê a sentinela — se a função do aluno tiver
# consumido a entrada (scanf/getchar escondido), a leitura dessincroniza e sai
# "SENTINELA-VIOLADA" => Wrong Answer determinístico, com o motivo visível no diff.
cat > /tmp/rwdir/__judge_main.c <<'EOF'
#include <stdio.h>

int soma(int a, int b);                      /* EDIT-ME: protótipo da função do aluno */

int main(void){
  int n;
  if (scanf("%d", &n) != 1) return 0;        /* nº de casos */
  for (int i = 0; i < n; i++) {
    int a, b;                                /* EDIT-ME: leitura dos parâmetros */
    if (scanf("%d %d", &a, &b) != 2) { printf("ENTRADA-CURTA\n"); return 0; }
    printf("%d\n", soma(a, b));              /* EDIT-ME: chamada + impressão */
  }
  int sentinela;                             /* a funcao do aluno leu a entrada? */
  if (scanf("%d", &sentinela) != 1 || sentinela != 424242) {
    printf("SENTINELA-VIOLADA (a funcao consumiu a entrada?)\n");
  }
  return 0;
}
EOF

# (opcional) BAN de funções por grep no fonte do aluno — descomente e edite. Limitações:
# grep não distingue comentário/alias/macro; p/ valer de verdade, restrinja `languages`
# do problema às linguagens com driver. Padrão: ver apc/seno e o template ban-funcoes-c.
# BANNED='exemplo1|exemplo2'
# STU=$(ls /tmp/rwdir/*.c | grep -v '__judge' | head -1)
# grep -qE "(^|[^[:alnum:]_])($BANNED)[[:space:]]*\(" "$STU" && {
#   echo "Uso de função proibida ($BANNED) — implemente manualmente." >&2; exit 1; }

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

cat > Makefile << 'EOF'
SRC=$(wildcard *.c)
CFLAGS=-lm -O2 -static

main: ${SRC}
	@gcc ${CFLAGS} $^ -o $@ -lm
	@echo BIN=$@
EOF

unset MAKELEVEL
make
