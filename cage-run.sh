#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#Foobar is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with Foobar.  If not, see <http://www.gnu.org/licenses/>.


LC_ALL=C
LANGUAGE=C

# Raiz da jaula: vazio = raiz do sistema (host, como sempre). Se setado (env CAGE_ROOT
# ou flag -R/--cage-root), a jaula usa esse rootfs (ex.: Ubuntu 24.04 com os compiladores).
CAGEROOT="${CAGE_ROOT:-}"

function printhelp()
{
  cat <<EOF
Usage: $0 <options>
-b, --bind                Bind file/dir to the cage
-d, --directory           Directory with all files to be run
-r, --run-script-filename Filename of script inside '-d' to run
              this script will actually run a binary file or an interpreter
              taking exposed input file
-i, --input-file          File to be processed
-o, --output-file         Output file to be generate as output of execution of -b
-s, --stderr-log-file     stderr log of the cage
-t, --time-log-file       File with execution times
-T, --time-limit          Limit of execution time, this should be greater than the problem TLE
-B, --bwrap-time-file     Time log of all bubblewrap execution
-w, --rw-dir              Exposes a directory as a persistend dir at '/tmp/rwdir'
              this option allows '-d','-i' and '-o' to be ommited
-R, --cage-root           Root filesystem to run the cage from (default: the host system
              root). Point it at an Ubuntu/other rootfs with all compilers installed for a
              reproducible toolchain. Falls back to the CAGE_ROOT env var.
-S, --shield-cpu          List of CPU's to be shielded
              this option will reserve a CPU, the program will not be able to
              run outside this group (must be invoked as root)
-U, --shield-user         User to be used to run inside the shield (must be invoked as root)
-M, --memlimit            Memory limit, in MB, to be allowed inside the shield (must be invoked as root)
EOF
}

TEMP=$(getopt -a -o 'hd:i:o:s:t:r:T:B:w:S:U:M:b:R:' -l 'bind:,memlimit:,shield-cpu:,shield-user:,rw-dir:,help,directory:,input-file:,output-file:,stderr-log-file:,time-log-file:,run-script-file:,time-limit:,bwrap-time-file:,cage-root:' -n "$0" -- "$@")

eval set -- "$TEMP"
unset TEMP
ARGS=0
declare -a missingparam
missingparam=(--directory --input-file --output-file --stderr-log-file --time-log-file --run-script-file --time-limit --bwrap-time-file)

BWRAPPARAM=
while [[ "$1" != "--" ]]; do
  case "$1" in
    '-S'|'--shield-cpu')
      SHIELDCPU="$2"
      shift 2
      continue
    ;;
    '-U'|'--shield-user')
      SHIELDUSER="$2"
      shift 2
      continue
    ;;
    '-M'|'--memlimit')
      MEMLIMIT="$2"
      shift 2
      continue
    ;;
    '-d'|'--directory')
      DIR="$2"
      shift 2
      ((ARGS++))
      unset missingparam[0]
      BWRAPPARAM+=" --ro-bind $DIR /tmp/dir"
      continue
    ;;
    '-R'|'--cage-root')
      CAGEROOT="$2"
      shift 2
      continue
    ;;
    '-b'|'--bind')
      DIR="$2"
      shift 2
      ((ARGS++))
      unset missingparam[0]
      # toolchain config (vinda dos prep.sh de linguagem): em modo rootfs pega do rootfs
      # se existir lá; senão (ou em modo host) binda do host. IO usa -d/-i/-o/-w/-r, não -b.
      if [[ -n "$CAGEROOT" && -e "$CAGEROOT$DIR" ]]; then
        BWRAPPARAM+=" --ro-bind $CAGEROOT$DIR $DIR"
      else
        BWRAPPARAM+=" --ro-bind $DIR $DIR"
      fi
      continue
    ;;
    '-i'|'--input-file')
      IN="$2"
      shift 2
      if [[ ! -e "$IN" ]]; then
        stat "$IN"
        exit 1
      fi
      ((ARGS++))
      unset missingparam[1]
      BWRAPPARAM+=" --ro-bind $IN /tmp/in"
      continue
    ;;
    '-o'|'--output-file')
      OUTPUT="$2"
      shift 2
      if [[ ! -e "$OUTPUT" ]]; then
        echo "Creating output file '$OUTPUT'" >&2
        touch $OUTPUT
      fi
      ((ARGS++))
      BWRAPPARAM+=" --bind $OUTPUT /tmp/out"
      unset missingparam[2]
      continue
    ;;
    '-T'|'--time-limit')
      TLE="$2"
      shift 2
      ((ARGS++))
      unset missingparam[3]
      continue
    ;;
    '-s'|'--stderr-log-file')
      STDERRLOG="$2"
      shift 2
      touch "$STDERRLOG"
      ((ARGS++))
      unset missingparam[4]
      continue
    ;;
    '-t'|'--time-log-file')
      TIMELOG="$2"
      shift 2
      touch "$TIMELOG"
      ((ARGS++))
      unset missingparam[5]
      continue
    ;;
    '-B'|'--bwrap-time-file')
      BWRAPTIMEFILE="$2"
      shift 2
      ((ARGS++))
      unset missingparam[6]
      continue
    ;;
    '-r'|'--run-script-file')
      RUNSCRIPTFILE="$2"
      shift 2
      if [[ ! -e "$RUNSCRIPTFILE" ]]; then
        stat "$RUNSCRIPTFILE"
        exit 1
      fi
      if [[ ! -x "$RUNSCRIPTFILE" ]]; then
        "$RUNSCRIPTFILE: is no executable"
        exit 2
      fi
      ((ARGS++))
      unset missingparam[7]
      continue
    ;;
    '-w'|'--rw-dir')
      RWDIR=$2
      shift 2
      if [[ ! -d $RWDIR ]]; then
        stat $RWDIR
        exit 3
      fi
      BWRAPPARAM+="--bind $RWDIR /tmp/rwdir"
      ((ARGS+=3))
      unset missingparam[2]
      unset missingparam[1]
      unset missingparam[0]
      continue
    ;;
    '-h'|'--help')
      printhelp
      exit 0
      continue
    ;;
    *)
      echo 'Internal error' >&2
      exit 1
      continue
    ;;
  esac
done

shift

if [[ "$*" != "" ]] ; then
  echo "Unknow param: $*"
  exit 2
fi

if [[ "${#missingparam[@]}" != "0" ]]; then
  echo "Missing options: ${missingparam[@]}"
  echo
  echo
  printhelp
  exit 3
fi

if ( [[ ! -n "$SHIELDUSER" ]] && [[ -n "$SHIELDCPU" ]] ) || ([[ -n "$SHIELDUSER" ]] && [[ ! -n "$SHIELDCPU" ]] ); then
  echo "--shield-user and --shield-cpu must be used together"
  echo
  printhelp
  exit 3
fi

[[ -n "$OUTPUT" ]] && touch $OUTPUT
[[ -n "$OUTPUTTEMPO" ]] && $OUTPUTTEMPO
if [[ -n "$BINARIO" ]] || [[ -n "$IN" ]]; then
  cat $BINARIO $IN > /dev/null
fi

if [[ "$USER" == "root" ]] && [[ -n "$(which cset)" ]]; then
  cset shield --cpu=$SHIELDCPU
  SHIELD="cset shield --user $SHIELDUSER --exec --"
  if [[ -n "$DIR" ]]; then
    chown -R $SHIELDUSER $DIR $(dirname $TIMELOG)
  fi
  if [[ -n "$RWDIR" ]]; then
    chown -R $SHIELDUSER $RWDIR $(dirname $TIMELOG)
  fi
  if [[ -n "$MEMLIMIT" ]]; then
    if [[ ! -d /sys/fs/cgroup/memory/mojtools ]]; then
      mkdir /sys/fs/cgroup/memory/mojtools
    fi
    echo $((MEMLIMIT*1024*1024)) > /sys/fs/cgroup/memory/mojtools/memory.limit_in_bytes
    echo $$ > /sys/fs/cgroup/memory/mojtools/tasks
  fi

fi

SAFETLE=$(echo "$TLE + 1"|bc -l)

# Montagem da RAIZ da jaula + mounts dinâmicos/IO. Default (CAGEROOT vazio) = userland do
# host (igual a sempre). Com CAGEROOT setado, a jaula usa o rootfs inteiro como '/' (ro) e só
# sobrepõe /proc,/dev,/tmp,/var,/run/user — todo o toolchain (/usr,/lib,/etc/...) vem do rootfs.
# O usrmerge do Ubuntu (/bin->/usr/bin etc.) resolve sozinho ao bindar o rootfs inteiro como '/'.
if [[ -n "$CAGEROOT" ]]; then
  if [[ ! -d "$CAGEROOT" ]]; then
    echo "cage-run: CAGE_ROOT inexistente ou não é diretório: $CAGEROOT" >&2
    exit 4
  fi
  ROOTBINDS="--ro-bind $CAGEROOT / --dir /tmp --dir /var --symlink ../tmp var/tmp --proc /proc --dev /dev --dir /run/user/$(id -u)"
else
  ROOTBINDS="--ro-bind /usr /usr --dir /tmp --dir /var --ro-bind /etc/alternatives /etc/alternatives --ro-bind /etc/localtime /etc/localtime --symlink ../tmp var/tmp --proc /proc --dev /dev --ro-bind /lib /lib --ro-bind /lib64 /lib64 --ro-bind /bin /bin --ro-bind /sbin /sbin --dir /run/user/$(id -u)"
fi

(exec /usr/bin/time -f "real %e\nuser %U\nsys %S\nres %M\ncpu %P" -o $BWRAPTIMEFILE timeout "$SAFETLE" $SHIELD bwrap $ROOTBINDS \
  --chdir / \
  --unshare-all \
  --die-with-parent \
  --file 11 /etc/passwd \
  --file 12 /etc/group \
  --ro-bind $RUNSCRIPTFILE /tmp/script\
  --bind $TIMELOG /tmp/timelog\
  --bind $STDERRLOG /tmp/stderrlog $BWRAPPARAM\
  --uid 65534 \
  --gid 65534 \
  /usr/bin/time -f "real %e\nuser %U\nsys %S\nres %M\ncpu %P" -o /tmp/timelog timeout $TLE /tmp/script) \
  11< <(getent passwd 65534) \
  12< <(getent group 65534)
