#!/bin/bash

# Sem binds de /etc: o cage-run monta o /etc inteiro da raiz escolhida (ver lang/java/prep.sh).

[[ ! -e /tmp/rars.jar ]] && wget https://github.com/TheThirdOne/rars/releases/download/v1.5/rars1_5.jar -O /tmp/rars.jar
cp /tmp/rars.jar $1/
