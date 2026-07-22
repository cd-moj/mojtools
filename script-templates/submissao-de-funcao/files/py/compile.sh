#!/bin/bash
# Driver de submissão-de-função (Python) — TEMPLATE. O arquivo do aluno é CONCATENADO com
# este rabo de driver (mesmo namespace): a função fica visível direto. EDIT-ME: leitura e
# chamada. Guia: mojtools/docs/submissao-de-funcao.md
#
# ATENÇÃO (Python): TODO código top-level do aluno RODA na concatenação (inclusive
# `if __name__ == '__main__':` — o módulo É __main__). O enunciado deve pedir SÓ a função.
# O driver lê a stdin INTEIRA de uma vez, então uma função que chame input() recebe EOF
# (vira RE/EOFError) — e a SENTINELA (última linha 424242 de todo teste) confere a
# estrutura da entrada mesmo assim.
exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

STU=$(ls | grep -iE '\.py3?$' | grep -v '^__judge' | head -1)

{
  cat "$STU"
  cat <<'PY'

import sys as __sys
def __judge_main():
    __d = __sys.stdin.read().split()
    __i = 0
    n = int(__d[__i]); __i += 1
    for _ in range(n):
        a = int(__d[__i]); b = int(__d[__i+1]); __i += 2   # EDIT-ME: leitura
        print(soma(a, b))                                  # EDIT-ME: chamada + impressão
    if __i >= len(__d) or __d[__i] != "424242":            # a entrada casa com o esperado?
        print("SENTINELA-VIOLADA (entrada malformada ou consumida)")
__judge_main()
PY
} > __judge_run.py

echo BIN=__judge_run.py
