#!/bin/bash
# scripts/c/prep.sh (instalado por mojtools/interactive/install-interactive.sh) — PREP do
# PROBLEMA INTERATIVO: materializa o ÁRBITRO executável em $1/arbitro (o $workdir, que a
# jaula monta RO em /tmp/dir na execução).
#
# É SOURCED pelo build-and-test NO HOST (antes da compilação), com $1 = workdir e
# $PROBLEMTEMPLATEDIR no ambiente — por isso NUNCA usar exit (só return). O árbitro vem de
# scripts/arbitro.{cpp,cc,py,sh} (o primeiro que existir) ou de um scripts/arbitro pronto.
# C++ é compilado NO HOST com -static (o binário roda DENTRO do rootfs da jaula) e cacheado
# FORA de scripts/ ($pkg/.arbitro-cache — não entra no tl-checksum; o FONTE entra, então
# mudar o árbitro recalibra e o hash novo recompila). Sem g++ no host, cai p/ o g++ do
# rootfs (CAGE_ROOT) via bwrap.

_ia_pkg="$PROBLEMTEMPLATEDIR"
_ia_dst="$1/arbitro"
_ia_ok=0

if [[ -f "$_ia_pkg/scripts/arbitro.cpp" || -f "$_ia_pkg/scripts/arbitro.cc" ]]; then
  _ia_src="$_ia_pkg/scripts/arbitro.cpp"; [[ -f "$_ia_src" ]] || _ia_src="$_ia_pkg/scripts/arbitro.cc"
  _ia_cache="$_ia_pkg/.arbitro-cache"
  _ia_hash="$(cat "$_ia_src" <(g++ --version 2>/dev/null || true) 2>/dev/null | sha256sum | cut -c1-16)"
  _ia_bin="$_ia_cache/arbitro.$_ia_hash"
  if [[ ! -x "$_ia_bin" ]]; then
    mkdir -p "$_ia_cache" 2>/dev/null
    find "$_ia_cache" -maxdepth 1 -name 'arbitro.*' -delete 2>/dev/null
    if command -v g++ >/dev/null 2>&1; then
      g++ -O2 -std=gnu++17 -static -o "$_ia_bin.tmp" "$_ia_src" 2> "$_ia_cache/compile.log" \
        && mv -f "$_ia_bin.tmp" "$_ia_bin" && chmod +x "$_ia_bin"
    elif [[ -n "${CAGE_ROOT:-}" && -x "$CAGE_ROOT/usr/bin/g++" ]] && command -v bwrap >/dev/null 2>&1; then
      bwrap --die-with-parent --ro-bind "$CAGE_ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
            --bind "$_ia_pkg" "$_ia_pkg" --chdir "$_ia_pkg" \
            /usr/bin/g++ -O2 -std=gnu++17 -static -o "$_ia_bin.tmp" "$_ia_src" 2> "$_ia_cache/compile.log" \
        && mv -f "$_ia_bin.tmp" "$_ia_bin" && chmod +x "$_ia_bin"
    else
      echo "interactive/prep: nenhum g++ p/ compilar o árbitro" >&2
    fi
    [[ -x "$_ia_bin" ]] || { echo "interactive/prep: FALHA ao compilar o árbitro:" >&2; cat "$_ia_cache/compile.log" >&2 2>/dev/null; }
  fi
  [[ -x "$_ia_bin" ]] && cp -f "$_ia_bin" "$_ia_dst" && chmod +x "$_ia_dst" && _ia_ok=1
elif [[ -f "$_ia_pkg/scripts/arbitro.py" ]]; then
  if head -1 "$_ia_pkg/scripts/arbitro.py" | grep -q '^#!'; then
    cp -f "$_ia_pkg/scripts/arbitro.py" "$_ia_dst"
  else
    { echo '#!/usr/bin/env python3'; cat "$_ia_pkg/scripts/arbitro.py"; } > "$_ia_dst"
  fi
  chmod +x "$_ia_dst" && _ia_ok=1
elif [[ -f "$_ia_pkg/scripts/arbitro.sh" ]]; then
  if head -1 "$_ia_pkg/scripts/arbitro.sh" | grep -q '^#!'; then
    cp -f "$_ia_pkg/scripts/arbitro.sh" "$_ia_dst"
  else
    { echo '#!/bin/bash'; cat "$_ia_pkg/scripts/arbitro.sh"; } > "$_ia_dst"
  fi
  chmod +x "$_ia_dst" && _ia_ok=1
elif [[ -x "$_ia_pkg/scripts/arbitro" ]]; then
  cp -f "$_ia_pkg/scripts/arbitro" "$_ia_dst" && chmod +x "$_ia_dst" && _ia_ok=1
fi

# sem árbitro, o run.sh interativo não tem o que rodar -> /tmp/out vazio -> UE (visível)
(( _ia_ok )) || echo "interactive/prep: árbitro NÃO materializado (scripts/arbitro.{cpp,py,sh} ausente ou falhou)" >&2
unset _ia_pkg _ia_dst _ia_src _ia_cache _ia_hash _ia_bin _ia_ok
