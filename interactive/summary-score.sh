#!/bin/bash
# scripts/summary.sh (instalado por install-interactive.sh --score) — veredicto FINAL de
# problema interativo de RANKING/score: soma o SCORE dos testes aceitos (ecoado pelo
# compare genérico como "SCORE=<n>" no log .compare de cada teste).
#
# É SOURCED pelo build-and-test no fim do julgamento, com o contexto: PROBLEMTEMPLATEDIR,
# workdirbase, LOG(), TOTALTESTS, log.verdictall (mapa VERDICT[teste]=veredicto). Pode
# sobrescrever FINALRESP/SCORE/SCORE_MAX/SCORE_KIND (contrato do report.env). Qualquer
# teste WA zera a pontuação (jogada inválida invalida o rank); SCORE não-numérico conta 0.

TOTALSCORE=0
SOLVES=0
TOTAL=0
WA=0
SOLVESTRING=""
declare -A VERDICT
source "$workdirbase/log.verdictall"

LOG "#SUMMARY (interativo/rank)"
for INPUT in "$PROBLEMTEMPLATEDIR"/tests/input/*; do
  FILE="$(basename "$INPUT")"
  ((TOTAL++))
  V="${VERDICT[$FILE]:-}"
  SOLVESTRING+="${V:0:1}"; [[ -z "$V" ]] && SOLVESTRING+="."
  SCORE=0
  if [[ "$V" =~ AC ]]; then
    SCORE="$(grep -m1 '^SCORE=' "$workdirbase/$FILE-log.compare" 2>/dev/null | cut -d= -f2-)"
    # score precisa ser numérico p/ somar; info não-numérica conta 0 (e fica no log)
    [[ "$SCORE" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || SCORE=0
    TOTALSCORE="$(bc -l <<< "$TOTALSCORE+($SCORE)")"
    ((SOLVES++))
  elif [[ "$V" == "WA" ]]; then
    ((WA++))
  fi
  LOG "- $FILE: ${V:-não executado} score=$SCORE"
done

if (( WA > 0 )); then
  TOTALSCORE=0
  FINALRESP="Wrong Answer, Score 0, $SOLVESTRING ($SOLVES/$TOTAL)"
else
  FINALRESP="Accepted, Score $TOTALSCORE, $SOLVESTRING ($SOLVES/$TOTAL)"
fi
LOG "- Total: $TOTALSCORE ($SOLVES/$TOTAL) WA=$WA"
LOG "- FINALRESP: $FINALRESP"

# report.env estruturado: score inteiro (arredonda p/ baixo), kind próprio de ranking
SCORE="$(bc <<< "$TOTALSCORE/1" 2>/dev/null)"; [[ "$SCORE" =~ ^-?[0-9]+$ ]] || SCORE=0
SCORE_MAX=$SCORE
SCORE_KIND=rank
