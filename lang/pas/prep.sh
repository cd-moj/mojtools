#!/bin/bash
# O /etc/fpc.cfg já vem no /etc inteiro montado pelo cage-run (host ou rootfs) — o fpc o acha
# no lugar padrão. A cópia p/ o workdir fica só como FALLBACK (o fpc também procura no cwd;
# cobre raiz exótica sem /etc/fpc.cfg).
cp "${CAGE_ROOT:-}/etc/fpc.cfg" "$1/" 2>/dev/null || cp /etc/fpc.cfg "$1/" 2>/dev/null || true
