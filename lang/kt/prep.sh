#!/bin/bash

# O /etc (java.security & cia.) já vem inteiro da raiz escolhida (cage-run). Só falta o
# compilador Kotlin em modo HOST (/opt não é bindado por default; no rootfs ele já vem).
if [[ -z "${CAGE_ROOT:-}" || "$CAGE_ROOT" == host ]]; then
  [[ -e /opt/kotlin ]] && EXTRABINDINGS+="-b /opt/kotlin"
fi
