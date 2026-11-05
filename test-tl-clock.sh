#!/bin/bash
# test-tl-clock.sh — o RELÓGIO do TL (05/11/2026): TLCLOCK=cpu no conf cobra o TL pelo tempo de CPU — o cpu.stat do
# CGROUP do escopo (MOJ_CAGE_CPUSTAT), ou, sem escopo, o user+sys do timelog de DENTRO — e a parede vira só um teto
# maior (WALLCAP = max(3×TL, ⌈CPUCAP⌉+1, WALLTL)), que pega quem dorme ou fica bloqueado. O padrão (parede) não muda
# NADA: enquanto o git HEAD não tem o TLCLOCK, o run-trace é comparado com o do build-and-test de lá.
#
# Roda o build-and-test.sh REAL numa cópia do mojtools com um cage-run.sh FALSO que decide pelo NOME do teste e
# imita a jaula real (bancada num juiz, 05/11/2026): o timelog de FORA (-B) marca user 0.00 SEMPRE (o bwrap não repassa
# o rusage), o de dentro (-t) não vê o filho órfão, e o cpu.stat do escopo vê tudo (FAKE_NOCGROUP=1 = juiz sem escopo):
#   xcpu   = 0,3 s de parede e 2 s de CPU (threads)      xslow = 2,5 s de parede (bloqueado) e 0,2 s de CPU
#   xsleep = morre no teto de parede (-T), rc 124          xorph = filho órfão: 3 s de CPU só no cgroup
#   x124   = sai com 124 sem passar do teto                xnoin = ignora SIGTERM: timelog de dentro vazio, fora ≥ -T
#   xxcpu  = morto por SIGXCPU no teto de CPU (rc 152)
# Cada execução anota "<teste> T=<-T> CPU=<MOJ_CAGE_CPUSEC>" em $RUNLOG. Sem jaula, sem rede. `make test-tl-clock`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:400}"; ((fail++)); fi; }

FAKE='#!/bin/bash
IN=""; OUT=""; TLOG=""; RW=""; SERR=""; BW=""; T=""
while (( $# )); do case "$1" in
  -i) IN="$2"; shift 2;; -o) OUT="$2"; shift 2;; -t) TLOG="$2"; shift 2;; -w) RW="$2"; shift 2;;
  -s) SERR="$2"; shift 2;; -B) BW="$2"; shift 2;; -T) T="$2"; shift 2;; -r|-d|-R|-M|-b|-S|-U|-C) shift 2;; *) shift;; esac; done
[[ -n "$SERR" ]] && : > "$SERR"
if [[ -n "$RW" && -z "$IN" ]]; then echo "BIN=sol" > "$OUT"; : > "$TLOG"; : > "$BW"; echo "compile T=$T CPU=${MOJ_CAGE_CPUSEC:-}" >> "$RUNLOG"; exit 0; fi
name="$(basename "$IN")"; real=0.05 user=0.03 sys=0.01 ouser="" rc=0 inner=1 oreal=""
echo "$name T=$T CPU=${MOJ_CAGE_CPUSEC:-}" >> "$RUNLOG"
case "$name" in
  *xcpu*)  real=0.30; user=1.90; sys=0.10 ;;
  *xslow*) real=2.50; user=0.15; sys=0.05 ;;
  *xsleep*) real="$T"; user=0.00; sys=0.00; rc=124 ;;
  *xorph*) real=1.50; user=0.01; sys=0.00; ouser=3.00 ;;
  *x124*)  rc=124 ;;
  *xnoin*) inner=0; user=0.00; sys=0.00; oreal="$(awk -v t="$T" "BEGIN{print t+1}")"; rc=124 ;;
  *xxcpu*) real="${MOJ_CAGE_CPUSEC:-9}"; user="${MOJ_CAGE_CPUSEC:-9}"; sys=0.00; rc=152 ;;
esac
cat "$IN" > "$OUT"
if (( inner )); then printf "real %s\nuser %s\nsys %s\nres 100\ncpu 99%%\n" "$real" "$user" "$sys" > "$TLOG"; else : > "$TLOG"; fi
printf "real %s\nuser 0.00\nsys 0.00\nres 100\ncpu 0%%\n" "${oreal:-$real}" > "$BW"
if [[ -n "${MOJ_CAGE_CPUSTAT:-}" && -z "${FAKE_NOCGROUP:-}" ]]; then
  printf "usage_usec %s\nuser_usec 0\nsystem_usec 0\n" "$(awk -v u="${ouser:-$user}" -v s="$sys" "BEGIN{printf \"%d\", (u + s) * 1000000}")" > "$MOJ_CAGE_CPUSTAT"
fi
echo "$name STAT=${MOJ_CAGE_CPUSTAT:+sim}" >> "$RUNLOG.stat"
exit "$rc"'

mkh(){  # mkh <dir> <build-and-test.sh de origem>
  mkdir -p "$1"
  cp "$2" "$1/build-and-test.sh"
  cp "$MT"/gen-report.sh "$MT"/lang-canon.sh "$MT"/score-summary.sh "$MT"/tl-methods.sh "$1"/ 2>/dev/null
  cp -r "$MT"/lang "$1"/lang
  printf '%s\n' "$FAKE" > "$1/cage-run.sh"; chmod +x "$1/cage-run.sh"
}
H="$W/mt"; mkh "$H" "$MT/build-and-test.sh"
export RUNLOG="$W/runs"

# pacote: <conf extra> <testes…>
mkpkg(){
  P="$W/pkg"; rm -rf "$P"; mkdir -p "$P/tests/input" "$P/tests/output"; : > "$RUNLOG"; : > "$RUNLOG.stat"
  printf 'ULIMITS[-u]=%s\n%s\n' "$(ulimit -Hu)" "$1" > "$P/conf"
  shift
  local t; for t in "$@"; do printf '%s\n' "$t" > "$P/tests/input/$t"; cp "$P/tests/input/$t" "$P/tests/output/$t"; done
  printf 'TL[c]=1\nTL[default]=1\n' > "$P/tl"
  printf 'int main(){return 0;}\n' > "$W/sol.c"
}
run(){  # run [dir do mojtools] [env…]
  local h="${1:-$H}" out; shift 2>/dev/null
  out="$(cd "$h" && env MOJ_PARALLEL=1 "$@" bash build-and-test.sh c "$W/sol.c" "$P" y 2>/dev/null)"
  WB="$(head -n1 <<<"$out")"; FIN="$(tail -n1 <<<"$out")"; TR="$WB/run-trace.log"
  DBG="FIN=$FIN | runs: $(tr '\n' ';' < "$RUNLOG") | $(cat "$WB/log.verdictall" 2>/dev/null | tr '\n' ' ')"
}
verdict(){ sed -n "s/^VERDICT\[$1\]=//p" "$WB/log.verdictall" | tail -1; }
renv(){ grep -m1 "^$1=" "$WB/report.env" | cut -d= -f2- | tr -d "'\""; }

TESTS=(t1 t2xcpu t3xslow t4xsleep t5xorph t6x124 t7xnoin t8xxcpu)

echo "== parede (o padrão): nada muda =="
mkpkg "" "${TESTS[@]}"
run
ck "sem teto de CPU na jaula; -T = o ETL de sempre (TL+2,2)" '! grep -q "CPU=[0-9]" "$RUNLOG" && grep -q "^t1 T=3.2 CPU=$" "$RUNLOG"'
ck "a parede decide: xcpu AC, xslow TLE, xsleep TLE, x124 RE_NZEC" '[[ "$(verdict t2xcpu)" == AC && "$(verdict t3xslow)" == TLE && "$(verdict t4xsleep)" == TLE && "$(verdict t6x124)" == RE_NZEC ]]'
ck "report.env sem TL_CLOCK/WALLCAP; sem -log.exectime; sem WALLTIME" '! grep -qE "^(TL_CLOCK|WALLCAP)=" "$WB/report.env" && ! ls "$WB"/*-log.exectime >/dev/null 2>&1 && ! grep -q "^WALLTIME" "$TR"'
ck "o cage-run não recebe MOJ_CAGE_CPUSTAT" '! grep -q "STAT=sim" "$RUNLOG.stat"'
ck "EXECTIME = o real de dentro" 'grep -qx "EXECTIME t2xcpu 0.30 AC" "$TR"'

# o run-trace da parede tem de sair IGUAL ao do build-and-test de antes (git HEAD), tirando caminho e relógio
# BAT_BASE=<ref> compara com outro commit (ex.: o pai do commit que trouxe o TLCLOCK, numa revisão)
if OLD="$(git -C "$MT" show "${BAT_BASE:-HEAD}:build-and-test.sh" 2>/dev/null)" && [[ -n "$OLD" ]] && ! grep -q "TLCLOCK" <<<"$OLD"; then
  printf '%s\n' "$OLD" > "$W/bat-old.sh"; HO="$W/mt-old"; mkh "$HO" "$W/bat-old.sh"
  norm(){ sed -E "s#$1#WB#g; s#$W#W#g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}[ T_][0-9:.,+-]+/DATE/g; s/(Starting|Ending|Finished) at .*/\1 at DATE/; s/(Total time|Total build-and-test time|TOTALTIME|tempo total).*/\1 X/I" "$2"; }
  run; NEWWB="$WB"; norm "$NEWWB" "$TR" > "$W/new.trace"
  run "$HO"; norm "$WB" "$TR" > "$W/old.trace"
  DBG="$(diff "$W/old.trace" "$W/new.trace" | head -20 | tr "\n" "~")"
  ck "run-trace da parede idêntico ao do build-and-test de antes" 'diff -q "$W/old.trace" "$W/new.trace" >/dev/null'
else
  echo "  (sem o build-and-test de antes no git: pulando a comparação do run-trace)"
fi

echo "== CPU (TLCLOCK=cpu): o cgroup do escopo decide, a parede é só o teto =="
mkpkg "TLCLOCK=cpu" "${TESTS[@]}"
run
ck "teto de CPU 4 s (⌈TL+2,2⌉) e de parede 5 s (teto de CPU + 1 > 3×TL) nos testes" 'grep -q "^t1 T=5.00 CPU=4$" "$RUNLOG"'
ck "o cage-run recebe MOJ_CAGE_CPUSTAT nos testes" 'grep -q "^t1 STAT=sim" "$RUNLOG.stat"'
ck "a compilação NÃO leva o teto de CPU" 'grep -q "^compile T=30 CPU=$" "$RUNLOG"'
ck "xcpu (2 s de CPU em 0,3 s de parede) = TLE"          '[[ "$(verdict t2xcpu)" == TLE ]]'
ck "xslow (2,5 s de parede, 0,2 s de CPU) = AC"           '[[ "$(verdict t3xslow)" == AC ]]'
ck "xsleep (morto no teto de parede, rc 124) = TLE, não RE" '[[ "$(verdict t4xsleep)" == TLE ]]'
ck "xorph (CPU do órfão só no cgroup) = TLE"            '[[ "$(verdict t5xorph)" == TLE ]]'
ck "x124 (sai com 124 antes do teto) = RE_NZEC"           '[[ "$(verdict t6x124)" == RE_NZEC ]]'
ck "xnoin (sem timelog de dentro, fora ≥ teto) = TLE"     '[[ "$(verdict t7xnoin)" == TLE ]]'
ck "xxcpu (SIGXCPU no teto de CPU) = TLE"                 '[[ "$(verdict t8xxcpu)" == TLE ]]'
ck "t1 = AC; EXECTIME com o CPU do cgroup (0,03+0,01)"   '[[ "$(verdict t1)" == AC ]] && grep -qx "EXECTIME t1 0.04 AC" "$TR"'
ck "-log.exectime = o tempo cobrado"                      '[[ "$(cat "$WB/t3xslow-log.exectime")" == 0.20 && "$(cat "$WB/t5xorph-log.exectime")" == 3.00 ]]'
ck "a marca da morte pela parede: xsleep e xnoin têm, xxcpu (SIGXCPU) e t1 não" '[[ -e "$WB/t4xsleep-log.wallkill" && -e "$WB/t7xnoin-log.wallkill" && ! -e "$WB/t8xxcpu-log.wallkill" && ! -e "$WB/t1-log.wallkill" ]]'
ck "linha WALLTIME própria (a EXECTIME não ganha campo)"  'grep -qx "WALLTIME t3xslow 2.50" "$TR" && ! grep -qE "^EXECTIME [^ ]+ [^ ]+ [^ ]+ " "$TR"'
ck "report.env: TL_CLOCK=cpu, WALLCAP=5.00, ETL=4 (o teto do tempo cobrado), fonte cgroup" '[[ "$(renv TL_CLOCK)" == cpu && "$(renv WALLCAP)" == 5.00 && "$(renv ETL)" == 4 && "$(renv TL_CPU_SOURCE)" == cgroup ]]'
ck "o trace diz a fonte do CPU" 'grep -q "Execution Time is CPU time (source: cgroup)" "$TR"'
ck "o report diz que o tempo é de CPU"                    'grep -rqs "tempo de CPU" "$WB"/report.org "$WB"/report.html'

echo "== juiz SEM escopo (root, sem user manager): o timelog de DENTRO, sem os órfãos =="
run "$H" FAKE_NOCGROUP=1
ck "xcpu ainda TLE (as threads estão no timelog de dentro)" '[[ "$(verdict t2xcpu)" == TLE ]]'
ck "xorph passa: o órfão não está no timelog de dentro (o limite conhecido; o report diz a fonte)" '[[ "$(verdict t5xorph)" == AC && "$(renv TL_CPU_SOURCE)" == timelog ]]'
ck "o timelog de FORA nunca entra no CPU (xslow: 0,2 s de dentro, não 0)" 'grep -qx "EXECTIME t3xslow 0.20 AC" "$TR"'

echo "== WALLTL sobe o teto de parede; 3×TL vence quando é maior =="
mkpkg $'TLCLOCK=cpu\nWALLTL=10' t1
run
ck "WALLTL=10 → -T 10.00" 'grep -q "^t1 T=10.00 CPU=4$" "$RUNLOG"'
mkpkg $'TLCLOCK=cpu\nWALLTL=2' t1
run
ck "WALLTL abaixo do mínimo não baixa o teto (5 s)" 'grep -q "^t1 T=5.00 CPU=4$" "$RUNLOG"'
mkpkg $'TLCLOCK=cpu\nTLOVERRIDE[default]=3' t1
run
ck "TL efetivo 3 s (TLOVERRIDE): parede 9 s (3×TL > 6+1), CPU 6 s (⌈3+2,2⌉)" 'grep -q "^t1 T=9.00 CPU=6$" "$RUNLOG"'
mkpkg "TLCLOCK=parede" t1
run
ck "valor desconhecido = parede" 'grep -q "^t1 T=3.2 CPU=$" "$RUNLOG"'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
