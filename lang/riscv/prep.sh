#!/bin/bash

# Sem binds de /etc: o cage-run monta o /etc inteiro da raiz escolhida (ver lang/java/prep.sh).

# rars.jar em cache POR MÁQUINA (1 download), com flock + download atômico (mktemp+mv):
# slots concorrentes nunca leem um jar pela metade nem disputam um /tmp fixo (o antigo
# /tmp/rars.jar sem lock entregava jar truncado a quem chegasse durante o wget).
# Este arquivo é SOURCED pelo build-and-test ($1 = workdir): vars prefixadas, sem exit.
_rars_dir="${MOJ_RARS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/moj}"
_rars_jar="$_rars_dir/rars1_5.jar"
mkdir -p "$_rars_dir" 2>/dev/null
if [[ ! -s "$_rars_jar" ]]; then
  (
    flock 9
    if [[ ! -s "$_rars_jar" ]]; then
      _rars_tmp="$(mktemp "$_rars_dir/.rars.XXXXXX")" \
        && wget -q https://github.com/TheThirdOne/rars/releases/download/v1.5/rars1_5.jar -O "$_rars_tmp" \
        && mv -f "$_rars_tmp" "$_rars_jar" || rm -f "$_rars_tmp"
    fi
  ) 9>"$_rars_jar.lock"
fi
cp "$_rars_jar" "$1/rars.jar"
