#!/bin/bash

# Binds de config do java valem SÓ em modo HOST (trazem o /etc/java* do host p/ a jaula).
# No ROOTFS a jaula já tem o próprio /etc/java-21-openjdk — e bindar um /etc/java que só
# existe no host quebra o bwrap (mkdir em /etc read-only: "Can't mkdir /etc/java").
if [[ -z "${CAGE_ROOT:-}" || "$CAGE_ROOT" == host ]]; then
  [[ -e /etc/java-21-openjdk/ ]] && EXTRABINDINGS+="-b /etc/java-21-openjdk/"
  [[ -e /etc/java ]] && EXTRABINDINGS+=" -b /etc/java"
fi

