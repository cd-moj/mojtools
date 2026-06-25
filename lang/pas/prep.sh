#!/bin/bash
# Copia o fpc.cfg p/ o workdir (o fpc também procura no cwd). Em modo rootfs (CAGE_ROOT
# setado), pega o do rootfs; vazio = /etc/fpc.cfg do host, como sempre.
cp "${CAGE_ROOT:-}/etc/fpc.cfg" "$1/" 2>/dev/null || cp /etc/fpc.cfg "$1/" 2>/dev/null
