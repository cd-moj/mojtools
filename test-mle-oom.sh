#!/bin/bash
# test-mle-oom.sh — morte por MEMÓRIA vira MLE, não RE (09/11/2026; LATAM: 29 envios que estouraram a memória saíram
# como Runtime Error).
#
# O teto duro do cgroup mata o programa com SIGKILL (exit 137), e a cadeia do _verdict_for dizia RE. Agora:
#   1. `oom_kill` > 0 no memory.events do escopo (o cage-run o grava em MOJ_CAGE_MEMEVENTS) = MLE, com ou sem MEMLIMITMB;
#   2. sem esse arquivo: o RSS medido acima do MEMLIMITMB num teste que morreu = MLE;
#   3. o TLE vence (estourou o tempo antes); o RE sem sinal de memória segue RE;
#   4. o MLE para a execução com STOPWHEN_RE=y (era assim enquanto saía como RE).
#
# Roda o build-and-test.sh REAL numa cópia do mojtools com um cage-run.sh FALSO que decide pelo NOME do teste:
#   xoom  = oom_kill 1, exit 137 · xoomnz = oom_kill 1, exit 1 · xkill = exit 137 e RSS de 1 GB, sem memory.events
#   xsegv = exit 139, oom_kill 0 · xbig = AC com RSS de 1 GB · xtleoom = real 9 s, oom_kill 1, exit 137
#   xoomac = oom_kill 1, exit 0 e saída certa (um filho morto por memória; o principal terminou)
# Sem jaula, sem rede. `make test-mle`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:300}"; ((fail++)); fi; }

H="$W/mt"; mkdir -p "$H"
cp "$MT"/build-and-test.sh "$MT"/gen-report.sh "$MT"/lang-canon.sh "$MT"/score-summary.sh "$H"/
cp -r "$MT"/lang "$H"/lang
cat > "$H/cage-run.sh" <<'EOF'
#!/bin/bash
IN=""; OUT=""; TLOG=""; RW=""; SERR=""; BW=""
while (( $# )); do case "$1" in
  -i) IN="$2"; shift 2;; -o) OUT="$2"; shift 2;; -t) TLOG="$2"; shift 2;; -w) RW="$2"; shift 2;;
  -s) SERR="$2"; shift 2;; -B) BW="$2"; shift 2;; -T|-r|-d|-R|-M|-b|-S|-U|-C) shift 2;; *) shift;; esac; done
[[ -n "$BW" ]] && : > "$BW"; [[ -n "$SERR" ]] && : > "$SERR"
if [[ -n "$RW" && -z "$IN" ]]; then echo "BIN=sol" > "$OUT"; : > "$TLOG"; exit 0; fi   # compilação
name="$(basename "$IN")"; real=0.05; res=100; rc=0; oom=""
echo "$name" >> "$RUNLOG"
case "$name" in
  *xtleoom*) real=9; oom=1; rc=137 ;;
  *xoomnz*)  oom=1; rc=1 ;;
  *xoomac*)  oom=1 ;;
  *xoom*)    oom=1; rc=137 ;;
  *xkill*)   res=1048576; rc=137 ;;
  *xsegv*)   oom=0; rc=139 ;;
  *xbig*)    res=1048576 ;;
esac
# o memory.events só existe quando o escopo existe (o cage-run real não grava nada sem ele)
[[ -n "$oom" && -n "${MOJ_CAGE_MEMEVENTS:-}" ]] && printf 'low 0\nhigh 0\nmax 3\noom 1\noom_kill %s\n' "$oom" > "$MOJ_CAGE_MEMEVENTS"
(( rc == 0 )) && cat "$IN" > "$OUT" || : > "$OUT"
printf 'real %s\nuser 0\nsys 0\nres %s\ncpu 99%%\n' "$real" "$res" > "$TLOG"
exit "$rc"
EOF
chmod +x "$H/cage-run.sh"
export RUNLOG="$W/runs"

# pacote: <conf extra> <testes…>
mkpkg(){
  P="$W/pkg"; rm -rf "$P"; mkdir -p "$P/tests/input" "$P/tests/output"; : > "$RUNLOG"
  printf 'ULIMITS[-u]=%s\n%s\n' "$(ulimit -Hu)" "$1" > "$P/conf"
  shift
  local t; for t in "$@"; do printf '%s\n' "$t" > "$P/tests/input/$t"; cp "$P/tests/input/$t" "$P/tests/output/$t"; done
  printf 'TL[c]=1\nTL[default]=1\n' > "$P/tl"
  printf 'int main(){return 0;}\n' > "$W/sol.c"
}
run(){
  local out; out="$(cd "$H" && env MOJ_PARALLEL=1 bash build-and-test.sh c "$W/sol.c" "$P" y 2>/dev/null)"
  WB="$(head -n1 <<<"$out")"; FIN="$(tail -n1 <<<"$out")"
  SR=""; [[ -f "$WB/report.env" ]] && SR="$( source "$WB/report.env"; printf '%s' "$SMALLRESP" )"
  DBG="FIN=$FIN | SR=$SR | runs: $(tr '\n' ' ' < "$RUNLOG") | $(cat "$WB/log.verdictall" 2>/dev/null | tr '\n' ' ')"
}
v(){ sed -n "s/^VERDICT\[$1\]=//p" "$WB/log.verdictall" 2>/dev/null | tail -1; }
runs(){ grep -cx "$1" "$RUNLOG"; }

echo "== cada sinal, com MEMLIMITMB=256 =="
mkpkg "MEMLIMITMB=256" t1_xoom t2_xoomnz t3_xkill t4_xsegv t5_xbig t6_xtleoom t7 t8_xoomac
run
ck "oom_kill + exit 137 = MLE (era RE)"                '[[ "$(v t1_xoom)" == MLE ]]'
ck "oom_kill + exit 1 = MLE (era RE_NZEC)"             '[[ "$(v t2_xoomnz)" == MLE ]]'
ck "exit 137 + RSS acima do limite, sem memory.events = MLE" '[[ "$(v t3_xkill)" == MLE ]]'
ck "exit 139 sem sinal de memória = RE"                '[[ "$(v t4_xsegv)" == RE ]]'
ck "AC com RSS acima do limite = MLE (como sempre)"    '[[ "$(v t5_xbig)" == MLE ]]'
ck "TLE vence o oom_kill"                              '[[ "$(v t6_xtleoom)" == TLE ]]'
ck "teste normal = AC"                                 '[[ "$(v t7)" == AC ]]'
ck "filho morto por memória e saída certa = MLE (não AC)" '[[ "$(v t8_xoomac)" == MLE ]]'

echo "== sem MEMLIMITMB: o oom_kill decide sozinho; o RSS não =="
mkpkg "" t1_xoom t2_xkill t3
run
ck "oom_kill = MLE mesmo sem MEMLIMITMB"               '[[ "$(v t1_xoom)" == MLE ]]'
ck "exit 137 + RSS alto sem MEMLIMITMB = RE"           '[[ "$(v t2_xkill)" == RE ]]'

echo "== veredicto final e parada =="
mkpkg "MEMLIMITMB=256" t1 t2_xoom t3
run
ck "o MLE vira o veredicto da submissão"               '[[ "$SR" == MLE && "$FIN" == Memory* ]]'
ck "sem STOPWHEN o t3 roda"                            '[[ "$(runs t3)" == 1 ]]'
mkpkg $'MEMLIMITMB=256\nSTOPWHEN_RE=y' t1 t2_xoom t3
run
ck "STOPWHEN_RE=y para no MLE: o t3 não roda"          '[[ "$(runs t3)" == 0 && "$SR" == MLE ]]'
mkpkg $'MEMLIMITMB=256\nSTOPWHEN_WA=y' t1 t2_xoom t3
run
ck "STOPWHEN_WA não para no MLE"                       '[[ "$(runs t3)" == 1 ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
