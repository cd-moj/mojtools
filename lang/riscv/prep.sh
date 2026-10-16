#!/bin/bash

# Sem binds de /etc: o cage-run monta o /etc inteiro da raiz escolhida (ver lang/java/prep.sh).

# rars.jar em cache POR MÁQUINA (1 download), com flock + download atômico (mktemp+mv):
# slots concorrentes nunca leem um jar pela metade nem disputam um /tmp fixo (o antigo
# /tmp/rars.jar sem lock entregava jar truncado a quem chegasse durante o wget).
# Este arquivo é SOURCED pelo build-and-test ($1 = workdir): vars prefixadas, sem exit.
# O nome do cache LEVA A VERSÃO: trocar de versão = trocar o nome, e cada juiz baixa a nova no próximo job RISC-V
# (com o nome fixo, juiz que já tinha o jar ficava na versão velha e o novo baixava a outra — frota dividida). O jar só
# entra no cache se o sha256 bater: download truncado ou trocado deixa o cache vazio em vez de julgar com um simulador
# desconhecido. ⚠ Sem o jar o programa não roda e a saída sai VAZIA (WA, não Judge Error — o build-and-test não confere
# o prep): ao trocar a versão, rode um test-run RISC-V em cada juiz logo depois do pull, p/ o download acontecer sob
# os olhos de quem fez o deploy.
_rars_dir="${MOJ_RARS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/moj}"
_rars_jar="$_rars_dir/rars1_6.jar"
_rars_sha256=780f730eb457b1ba609e968accc2c8b77d8f92c3d9dbf30cc7fdb3cfb14e8c24
mkdir -p "$_rars_dir" 2>/dev/null
if [[ ! -s "$_rars_jar" ]]; then
  (
    flock 9
    if [[ ! -s "$_rars_jar" ]]; then
      _rars_tmp="$(mktemp "$_rars_dir/.rars.XXXXXX")" \
        && wget -q https://github.com/TheThirdOne/rars/releases/download/v1.6/rars1_6.jar -O "$_rars_tmp" \
        && [[ "$(sha256sum "$_rars_tmp" | cut -d' ' -f1)" == "$_rars_sha256" ]] \
        && mv -f "$_rars_tmp" "$_rars_jar" || rm -f "$_rars_tmp"
    fi
  ) 9>"$_rars_jar.lock"
fi
cp "$_rars_jar" "$1/rars.jar"
