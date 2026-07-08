#!/bin/bash
# scripts/compare.sh (instalado por mojtools/interactive/install-interactive.sh) — decide o
# veredicto de UM teste de problema INTERATIVO a partir do RESULTADO materializado pelo
# driver em /tmp/out ($1 = team_output):
#   vazio                       -> exit 13 (UE: árbitro não produziu resultado — anormal)
#   última linha "WRONG <..>"   -> exit  6 (Wrong Answer; o motivo vai p/ o log)
#   qualquer outra coisa        -> exit  4 (Accepted) + ecoa "SCORE=<resultado>" p/ o
#                                  summary somar (problemas de rank)
# $2 (saída esperada) e $3 (entrada) não são usados aqui — um compare CUSTOM do problema
# pode usá-los (ex.: tests/output como score de referência). Protocolo/tutorial:
# mojtools/docs/problema-interativo.md
TEAMOUTPUT="${1:?}"

if [[ ! -s "$TEAMOUTPUT" ]]; then
  echo "sem resultado do árbitro (saída vazia) — Unknown Error"
  exit 13
fi

RESULT="$(grep -v '^[[:space:]]*$' "$TEAMOUTPUT" | tail -n1)"
case "$RESULT" in
  WRONG*)
    echo "Wrong Answer: $RESULT"
    exit 6 ;;
esac

echo "SCORE=$RESULT"
exit 4
