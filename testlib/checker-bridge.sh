#!/bin/bash
# mojtools/testlib/checker-bridge.sh — BRIDGE de um checker TESTLIB PADRÃO para o contrato
# do juiz do MOJ. É a FONTE ÚNICA: o pacote NÃO carrega uma cópia disto, carrega um STUB
# (testlib/compare-stub.sh, instalado como scripts/compare.sh) que chama este arquivo. Assim
# um bug aqui se conserta EM UM LUGAR — e não em cada pacote já empacotado (foi exatamente o
# que aconteceu com o bind do bwrap abaixo: 198 pacotes nasceram com a cópia quebrada).
#
# Uso:  checker-bridge.sh [--pkg <dir do pacote>] <team_output> <answer> <input>
#       sem --pkg: deriva o pacote de $0/.. — COMPAT com o padrão antigo (bridge COPIADA
#       como scripts/compare.sh).
#
# O MOJ chama:      compare.sh <team_output> <answer> <input>   -> exit 4=AC 5=AC,PE 6=WA (outros=UE)
# O testlib quer:   checker <input> <team_output> <answer>      -> exit 0=ok 1=wa 2=pe 3=fail
#                                                                  (4=dirt 7=points 8=eof-inesperado)
# ATENÇÃO à semântica: o _pe da testlib ("saída fora do formato esperado/não parseável")
# NÃO é o PE do MOJ/BOCA ("resposta certa, só espaçamento difere" — aceito). _pe da
# testlib é resposta ERRADA => Wrong Answer, SEMPRE (idem _dirt e eof inesperado).
#
# O fonte viaja no pacote (scripts/checker.cpp, testlib PADRÃO — sem -DBOCA_SUPPORT); o
# testlib.h vem VENDORADO no mojtools (testlib/testlib.h; um scripts/testlib.h local, se
# existir, tem precedência). Compila no juiz na 1ª comparação (o compare roda FORA da jaula)
# e cacheia o binário FORA de scripts/ (não entra no tl-checksum). Guia de autoria:
# mojtools/docs/checker-testlib.md.
set -u

PKG=""
[[ "${1:-}" == --pkg ]] && { PKG="${2:?--pkg precisa do diretório do pacote}"; shift 2; }
TEAM="${1:?}"; ANS="${2:?}"; IN="${3:?}"
[[ -n "$PKG" ]] || PKG="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)"   # compat: bridge copiada no pacote

SRC="$PKG/scripts/checker.cpp"
[[ -f "$SRC" ]] || { echo "checker-bridge: scripts/checker.cpp não existe no pacote ($PKG)"; exit 7; }

# testlib.h: override do pacote > vendorado do mojtools (o build-and-test roda o compare
# com CWD = diretório do mojtools e EXPORTA MOJTOOLS_DIR)
MOJTOOLS_DIR="${MOJTOOLS_DIR:-$PWD}"
TESTLIB="$PKG/scripts/testlib.h"
[[ -f "$TESTLIB" ]] || TESTLIB="$MOJTOOLS_DIR/testlib/testlib.h"
[[ -f "$TESTLIB" ]] || { echo "checker-bridge: testlib.h não encontrado (nem em scripts/ nem em $MOJTOOLS_DIR/testlib/)"; exit 7; }

# gcc >= 15: o <bits/stdc++.h> não puxa mais cassert/cstring/cstdint transitivamente, e
# vários checkers do Polygon usam assert()/memset() sem incluir. Sem isto o checker NÃO
# COMPILA num juiz de gcc novo -> exit 7 -> TODO teste vira UE. Inofensivo no gcc antigo.
CFLAGS=(-O2 -std=gnu++17 -include cassert -include cstring -include cstdint)

# Cache do binário FORA de scripts/ (o tl-checksum cobre scripts/*: binário lá dentro
# divergiria o checksum do juiz do do servidor). Chave = fonte + testlib + o COMPILADOR que
# de fato vai compilar. Num juiz não há g++ no host (`g++ --version` vazio): sem a rootfs na
# chave, o binário sobreviveria a uma troca de rootfs.
CACHE="$PKG/.checker-cache"
ROOTFS_CC=""
[[ -n "${CAGE_ROOT:-}" && -x "$CAGE_ROOT/usr/bin/g++" ]] \
  && ROOTFS_CC="$CAGE_ROOT $(stat -c %Y "$CAGE_ROOT/usr/bin/g++" 2>/dev/null)"
HASH="$(cat "$SRC" "$TESTLIB" <(g++ --version 2>/dev/null || true) <(printf '%s\n' "$ROOTFS_CC") \
        2>/dev/null | sha256sum | cut -c1-16)"
BIN="$CACHE/checker.$HASH"

if [[ ! -x "$BIN" ]]; then
  mkdir -p "$CACHE" 2>/dev/null
  # LOCK (fd LOCAL ao bloco — nada de `exec 9>…`, que mexeria no shell inteiro): o juiz roda
  # vários slots em paralelo e a 1ª submissão de cada um cai aqui junto; sem trava, um apagaria
  # (find -delete) o binário que o outro acabou de gravar.
  {
    flock 9 2>/dev/null || true
    if [[ ! -x "$BIN" ]]; then                   # rechecar: outro slot pode ter compilado
      find "$CACHE" -maxdepth 1 -name 'checker.*' -delete 2>/dev/null   # versões antigas
      if command -v g++ >/dev/null 2>&1; then
        g++ "${CFLAGS[@]}" -o "$CACHE/checker.new" "$SRC" -I "$(dirname "$TESTLIB")" 2> "$CACHE/compile.log" \
          || { echo "checker-bridge: falha ao compilar o checker (g++ do host):"; cat "$CACHE/compile.log"; exit 7; }
      elif [[ -n "$ROOTFS_CC" ]] && command -v bwrap >/dev/null 2>&1; then
        # Sem g++ no host — o caso NORMAL num juiz (os compiladores moram na rootfs). Compila
        # com o g++ da rootfs, ESTÁTICO: o binário roda no HOST, fora da jaula.
        # TUDO entra SOB /tmp (o --tmpfs). A rootfs é montada READ-ONLY em /; bindar um caminho
        # do host lá dentro faz o bwrap tentar CRIAR o ponto de montagem na raiz RO:
        #   "bwrap: Can't mkdir parents for /…/pkg: Read-only file system"
        # => checker não compila => UE em TODO teste. Mesmo padrão do cage-run.sh.
        bwrap --die-with-parent --ro-bind "$CAGE_ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
              --ro-bind "$SRC" /tmp/checker.cpp --ro-bind "$TESTLIB" /tmp/testlib.h \
              --bind "$CACHE" /tmp/out --chdir /tmp \
              /usr/bin/g++ "${CFLAGS[@]}" -static -o /tmp/out/checker.new /tmp/checker.cpp -I /tmp \
              2> "$CACHE/compile.log" \
          || { echo "checker-bridge: falha ao compilar o checker (g++ da rootfs $CAGE_ROOT):"; cat "$CACHE/compile.log"; exit 7; }
      else
        echo "checker-bridge: nenhum g++ disponível (host sem g++ e sem CAGE_ROOT com toolchain)"; exit 7
      fi
      mv -f "$CACHE/checker.new" "$BIN" && chmod +x "$BIN"
    fi
  } 9>"$CACHE/.lock"
fi
[[ -x "$BIN" ]] || { echo "checker-bridge: binário do checker não foi produzido ($BIN)"; exit 7; }

# executa na interface PADRÃO do testlib; a mensagem do checker (stderr) vai p/ o log .compare
"$BIN" "$IN" "$TEAM" "$ANS"; rc=$?
case "$rc" in
  0)     exit 4 ;;   # _ok                        -> Accepted
  1|2|4|8) exit 6 ;; # _wa/_pe/_dirt/eof          -> Wrong Answer (o _pe da testlib é
                     #   "formato inválido/não parseável" = resposta errada; não confundir
                     #   com o AC,PE do MOJ, que é exclusivo do comparador diff default)
  3) echo "checker-bridge: checker devolveu _fail (rc=3) — gabarito/checker inválido"; exit 7 ;;
  7) echo "checker-bridge: checker devolveu _points (rc=7) — parcial por checker NÃO é suportado (use grupos em tests/score)"; exit 7 ;;
  *) echo "checker-bridge: exit inesperado do checker (rc=$rc)"; exit 7 ;;
esac
