#!/bin/bash

# binds de config do java só em modo HOST (no rootfs a jaula já tem o JDK próprio;
# bindar mountpoint inexistente quebra o bwrap — ver lang/java/prep.sh)
if [[ -z "${CAGE_ROOT:-}" || "$CAGE_ROOT" == host ]]; then
  [[ -e /etc/java-21-openjdk/ ]] && EXTRABINDINGS+="-b /etc/java-21-openjdk/"
  [[ -e /etc/java ]] && EXTRABINDINGS+=" -b /etc/java"
fi

[[ ! -e /tmp/rars.jar ]] && wget https://github.com/TheThirdOne/rars/releases/download/v1.5/rars1_5.jar -O /tmp/rars.jar
cp /tmp/rars.jar $1/
