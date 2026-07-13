#!/bin/bash
# scripts/summary.sh — STUB (instalado por mojtools/interactive/install-interactive.sh --score).
#
# O SUMMARY de RANKING (soma o SCORE dos testes aceitos) mora no MOJTOOLS (fonte única):
#   mojtools/interactive/summary-score.sh
# Este arquivo é só o PONTEIRO. Um problema que precise de summary PRÓPRIO substitui-o.
#
# É SOURCED pelo build-and-test NO HOST, no fim do julgamento (contexto: PROBLEMTEMPLATEDIR,
# workdirbase, LOG(), TOTALTESTS…; pode sobrescrever FINALRESP/SCORE/…) — nada de `exit`.
if [[ -f "${MOJTOOLS_DIR:-$PWD}/interactive/summary-score.sh" ]]; then
  source "${MOJTOOLS_DIR:-$PWD}/interactive/summary-score.sh"
else
  echo "summary.sh: summary do interativo não encontrado em '${MOJTOOLS_DIR:-$PWD}/interactive/summary-score.sh'" >&2
fi
