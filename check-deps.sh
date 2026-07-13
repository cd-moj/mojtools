#!/bin/bash
# check-deps.sh — doctor de dependências do MOJ (host de juiz + sandbox).
# Chamado pelo judge/install.sh (fase "doctor") e útil à mão. Lista o que falta.
#
# Uso: check-deps.sh [--rootfs DIR] [--quiet]
#   sem --rootfs  => modo HOST: os compiladores têm de estar no PATH do host.
#   --rootfs DIR  => modo ROOTFS: os compiladores moram no rootfs (jaula); o host
#                    só precisa das ferramentas de RUNTIME. Checa os compiladores
#                    dentro de DIR/usr/{,local/}bin em vez do PATH.
set -u

ROOTFS=""; QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rootfs) ROOTFS="${2:-}"; shift 2;;
    --quiet)  QUIET=1; shift;;
    -h|--help) sed -n '2,12p' "$0"; exit 0;;
    *) echo "check-deps: opção desconhecida: $1" >&2; exit 2;;
  esac
done

# Ferramentas de RUNTIME do host (fora da jaula ou dirigindo-a). SEMPRE no host.
HOST_HARD='bash jq curl bwrap timeout taskset flock getopt bc make diff awk sed grep
           tar gzip getent sha256sum nproc base64 mktemp pkill'
# Só no /usr/bin/time (GNU) — o cage-run chama por caminho absoluto.
HOST_HARD_PATHS='/usr/bin/time'
# Opcionais (degradam com aviso): cset (cgroup root), systemd-run (memlimit sem root),
# podman+unzip (construir rootfs), wget (lang/riscv baixa rars), nvidia-smi/rocm-smi (gpu).
HOST_SOFT='cset systemd-run podman unzip wget'

# Binário principal de cada linguagem aceita (basta UMA alternativa existir por grupo).
# Espelha judge/agent/inventory.sh _LANGBIN.
COMPILERS='gcc g++ javac java pypy3 python3 fpc mcs mono gccgo rustc ghc node swipl kotlinc spim dyalogscript'

_have_host()   { command -v "$1" >/dev/null 2>&1; }
# Dentro do rootfs, o binário da distro quase sempre é SYMLINK p/ caminho ABSOLUTO
# (/usr/bin/javac -> /etc/alternatives/javac -> /usr/lib/jvm/…). Visto do HOST esse alvo aponta p/
# FORA do rootfs, e um `-x` simples dá FALSO-NEGATIVO: javac/java/fpc/kotlinc/dyalogscript "somem"
# de um rootfs que os tem. Resolve a cadeia de symlinks DENTRO do rootfs.
_rootfs_exec() {  # <caminho absoluto dentro do rootfs>
  local p="$1" t n=0
  while [[ -L "$ROOTFS$p" ]]; do
    (( ++n > 10 )) && return 1                      # laço de symlink
    t="$(readlink "$ROOTFS$p")"
    case "$t" in /*) p="$t";; *) p="$(dirname "$p")/$t";; esac
  done
  [[ -x "$ROOTFS$p" ]]
}
_have_rootfs() { local b="$1"
  _rootfs_exec "/usr/local/bin/$b" || _rootfs_exec "/usr/bin/$b" || _rootfs_exec "/bin/$b"; }
_have_lang()   { if [[ -n "$ROOTFS" ]]; then _have_rootfs "$1"; else _have_host "$1"; fi; }

miss_hard=0 miss_soft=0 miss_lang=0
report() { (( QUIET )) || echo "$@"; }

report "== deps duros do HOST (runtime da jaula) =="
for d in $HOST_HARD; do _have_host "$d" || { report "  FALTA: $d"; ((miss_hard++)); }; done
for p in $HOST_HARD_PATHS; do [[ -x "$p" ]] || { report "  FALTA: $p"; ((miss_hard++)); }; done
(( miss_hard == 0 )) && report "  OK."

report "== deps opcionais do HOST =="
for d in $HOST_SOFT; do _have_host "$d" || { report "  ausente (opcional): $d"; ((miss_soft++)); }; done
(( miss_soft == 0 )) && report "  OK."

report "== compiladores/runtimes ($([[ -n "$ROOTFS" ]] && printf 'rootfs=%s' "$ROOTFS" || printf 'host')) =="
for c in $COMPILERS; do _have_lang "$c" || { report "  ausente: $c"; ((miss_lang++)); }; done
(( miss_lang == 0 )) && report "  OK (todos presentes)."

# Bit de execução dos scripts de linguagem — dep DURA, e não é firula: o cage-run.sh monta cada um
# como /tmp/script (bind READ-ONLY) e o executa DIRETO (`timeout $TLE /tmp/script`, sem `bash`).
# Sem +x é "Permission denied" e não dá nem p/ consertar de dentro da jaula. O `kt` nasceu 644 no git
# e Kotlin (linguagem oficial do ICPC) não rodava em juiz NENHUM provisionado do repositório.
report "== scripts de linguagem executáveis =="
_SELF="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
noexec=""
for f in "$_SELF"/lang/*/compile.sh "$_SELF"/lang/*/run.sh "$_SELF"/lang/*/compare.sh "$_SELF"/lang/compare.sh; do
  [[ -e "$f" ]] || continue
  [[ -x "$f" ]] || { noexec="$noexec ${f#"$_SELF"/}"; ((miss_hard++)); }
done
if [[ -n "$noexec" ]]; then
  report "  SEM +x (a jaula executa o script direto):$noexec"
  report "  conserte no REPO: git update-index --chmod=+x <arquivo>   (chmod local some no próximo clone)"
else report "  OK."; fi

report ""
report "resumo: duros_faltando=$miss_hard opcionais_ausentes=$miss_soft linguagens_ausentes=$miss_lang"
# exit != 0 SÓ se faltar dep DURO (o que impede o juiz de funcionar).
exit "$miss_hard"
