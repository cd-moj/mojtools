#!/bin/bash
# check-quoting.sh — INVENTÁRIO EXECUTÁVEL: o nome do arquivo do ALUNO nunca chega solto a um
# shell. Roda em `make check` (qualquer máquina, sem jaula).
#
# Por que existe: um time mandou `l(1).cpp` — a marca que o navegador gruda em download repetido,
# que ele nem escolheu — e levou **Compilation Error** (relato de 2026-08-24). O agente do juiz
# materializa a fonte PRESERVANDO o nome, o build-and-test a copia p/ dentro da jaula e o
# `lang/cpp/compile.sh` gera um Makefile cujo recipe o make entrega ao `/bin/sh` CRU:
#
#     /bin/sh: -c: line 1: syntax error near unexpected token `('
#     `g++ -lm -O2 -static -std=gnu++20 -pipe l(1).cpp -o l -lm'
#
# São três famílias, e as três já foram copiadas de linguagem em linguagem (é assim que o bug
# volta): o recipe do make, o `$BIN` dos run.sh e o `binfile.sh` — que é SOURCEADO dentro da
# jaula, então `BIN=l(1)` cru é erro de sintaxe do bash e mata a submissão no RUN.
#
# A defesa em profundidade termina aqui; quem garante nome sadio é a porta (o `safe_src_filename`
# do cdmoj, no /submit). Espaço, aliás, é IRREPARÁVEL dentro do make (whitespace É o separador
# de lista de prerequisito/target) — por isso o servidor o remove.
set -uo pipefail
cd "$(dirname "$0")" || exit 2
rc=0

# A) recipe do make (linha iniciada por TAB) com $^ / $@ sem aspas
bad="$(grep -Hn '^	' lang/*/compile.sh 2>/dev/null \
       | sed "s/'\$\^'//g; s/'\$@'//g; s/-o'\$@'//g; s/-out:'\$@'//g; s/\"BIN=\$@\"//g" \
       | grep '\$[\^@]')"
if [[ -n "$bad" ]]; then
  echo "RECIPE DE MAKE SEM ASPAS (o nome do aluno vai cru p/ o /bin/sh):"
  echo "$bad" | sed 's/^/    /'
  echo "  conserte: '\$^' e '\$@' entre aspas simples; @echo \"BIN=\$@\""
  rc=1
fi

# B) $BIN sem aspas nos run.sh (o BIN sai do nome do arquivo do aluno)
bad="$(grep -Hn '\$BIN' lang/*/run.sh interactive/run.sh 2>/dev/null \
       | sed 's/"\$BIN"//g' | grep '\$BIN')"
if [[ -n "$bad" ]]; then
  echo "\$BIN SEM ASPAS (nome do binário/fonte vem do aluno):"
  echo "$bad" | sed 's/^/    /'
  rc=1
fi

# C) o binfile.sh é SOURCEADO na jaula: o BIN tem de sair por %q
if ! grep -q "printf 'BIN=%q" build-and-test.sh; then
  echo "build-and-test.sh: o BIN do binfile.sh precisa sair por printf 'BIN=%q\\n' (é sourceado na jaula)"
  rc=1
fi

(( rc == 0 )) && echo "aspas ok (recipe de make, \$BIN dos run.sh, binfile.sh)"
exit $rc
