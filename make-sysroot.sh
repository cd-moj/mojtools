#!/bin/bash
# make-sysroot.sh — constrói um rootfs (Ubuntu 24.04 por padrão) com os compiladores das
# linguagens aceitas pelo MOJ e o EXPORTA p/ um diretório, p/ usar como raiz da jaula:
#   CAGE_ROOT=<dir>   (ou  cage-run.sh -R <dir>).
# Requer podman (rootless ok). NÃO precisa de root.
#
#   make-sysroot.sh [--base ubuntu:24.04] [--out DIR] [--tag moj-sysroot]
#                   [--pkgs "p1 p2 ..."] [--apl FILE.deb] [--no-export]
#
#   --base    imagem base OCI (ubuntu:24.04, debian:12, ...). Default: ubuntu:24.04
#   --out     diretório de saída do rootfs. Default: <mojtools>/sysroot/rootfs
#   --pkgs    lista de toolchains EXTRAS (override; "" = só o core C/C++/Java/Python/PyPy3)
#   --apl     instala o .deb do Dyalog APL (proprietário) numa camada extra
#   --no-export  só constrói a imagem (não exporta o diretório)
set -euo pipefail
SELF="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

BASE=ubuntu:24.04
OUT=""
TAG=moj-sysroot
APL=""
PKGS_SET=0; PKGS=""
EXPORT=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)  BASE="$2"; shift 2;;
    --out)   OUT="$2"; shift 2;;
    --tag)   TAG="$2"; shift 2;;
    --pkgs)  PKGS="$2"; PKGS_SET=1; shift 2;;
    --apl)   APL="$2"; shift 2;;
    --no-export) EXPORT=0; shift;;
    -h|--help) sed -n '2,18p' "$0"; exit 0;;
    *) echo "make-sysroot: opção desconhecida: $1" >&2; exit 2;;
  esac
done
[[ -n "$OUT" ]] || OUT="$SELF/sysroot/rootfs"
command -v podman >/dev/null 2>&1 || { echo "make-sysroot: preciso de 'podman' (rootless ok)" >&2; exit 1; }
[[ -f "$SELF/sysroot/Containerfile" ]] || { echo "make-sysroot: sem sysroot/Containerfile" >&2; exit 1; }

BUILDARGS=(--build-arg "BASE=$BASE")
(( PKGS_SET )) && BUILDARGS+=(--build-arg "PKGS=$PKGS")

echo "==> build da imagem $TAG (base=$BASE)"
podman build "${BUILDARGS[@]}" -t "$TAG" -f "$SELF/sysroot/Containerfile" "$SELF/sysroot"

# APL (Dyalog) opcional: camada extra com o .deb proprietário
if [[ -n "$APL" ]]; then
  [[ -f "$APL" ]] || { echo "make-sysroot: --apl: arquivo inexistente: $APL" >&2; exit 1; }
  echo "==> camada APL (Dyalog) a partir de $APL"
  cdir="$(mktemp -d)"; cp "$APL" "$cdir/dyalog.deb"
  cat > "$cdir/Containerfile" <<EOF
FROM $TAG
COPY dyalog.deb /tmp/dyalog.deb
RUN apt-get update && apt-get install -y /tmp/dyalog.deb && rm -f /tmp/dyalog.deb && rm -rf /var/lib/apt/lists/*
EOF
  podman build -t "$TAG" "$cdir"; rm -rf "$cdir"
fi

if (( EXPORT )); then
  echo "==> exportando rootfs p/ $OUT"
  mkdir -p "$OUT"
  cid="$(podman create "$TAG" true)"
  trap 'podman rm "$cid" >/dev/null 2>&1 || true' EXIT
  podman export "$cid" | tar -x -C "$OUT"
  podman rm "$cid" >/dev/null 2>&1 || true; trap - EXIT
  echo "==> pronto: $OUT"
  echo
  echo "use na jaula:"
  echo "  export CAGE_ROOT=$OUT          # global do juiz (agent.env)"
  echo "  # ou por linguagem: CAGE_ROOT_JAVA=$OUT"
  echo "  # ou direto: cage-run.sh -R $OUT ..."
else
  echo "==> imagem $TAG pronta (sem export)"
fi
