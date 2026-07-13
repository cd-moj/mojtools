#!/bin/bash
set -o pipefail

exec &>/tmp/stderrlog

#ulimit -a

cd /tmp/dir
source binfile.sh

# `dyalog -script` e NÃO `dyalogscript`: o wrapper `dyalogscript` ECOA no stdout a linha lida por
# ⍞ — a entrada do teste sairia grudada na resposta e TODA submissão APL viraria WA.
# Sem APLTRANS/APLKEYS: o /usr/bin/dyalog (via alternatives) já resolve o install sozinho; fixar
# /opt/mdyalog/<versão>/… quebra a cada upgrade (o .deb atual é 20.0; o caminho antigo era 19.0).
# O interpretador reclama de HOME não-gravável no stderr (inofensivo — vai p/ o stderrlog) e
# termina cada linha com CR: o `tr -d '\r'` deixa a saída como o aluno escreveu (sem isso o
# compare cai no `diff -b` e TODA submissão APL vira AC,PE).
# `pipefail` preserva o código de saída do dyalog (o RE_NZEC depende dele).
dyalog -s -script ./$BIN < /tmp/in | tr -d '\r' > /tmp/out
