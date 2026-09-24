#!/bin/bash
# test-parallel.sh — o POOL de testes do build-and-test.sh (24/09/2026): P workers sobre a fila de
# testes, cada um pinando a jaula no seu grupo de CPUs (cage-run -C), STOPWHEN visto por todo worker,
# liberação de cauda (MOJ_RELEASE_FILE) e antes do rerun serial de TLE, fallback sem env
# (P = min(nproc/k, MAXPARALLELTESTS); ALLOWPARALLELTEST=n ⇒ 1), o canal p/ a jaula (MOJ_TEST_CPUS /
# OMP_NUM_THREADS no binfile.sh) e o report ("P teste(s) × k CPU(s)").
# Roda o build-and-test REAL numa cópia do mojtools com um cage-run.sh FALSO (grava os argumentos
# recebidos, simula tempo/saída) e um `nproc` falso no PATH. Sem jaula, sem rede. `make test-parallel`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:300}"; ((fail++)); fi; }

# ---- cópia do mojtools com o cage-run FALSO -----------------------------------------------------
H="$W/mt"; mkdir -p "$H"
cp "$MT"/build-and-test.sh "$MT"/gen-report.sh "$MT"/lang-canon.sh "$H"/; cp -r "$MT"/lang "$H"/lang
cat > "$H/cage-run.sh" <<'EOF'
#!/bin/bash
# cage-run FALSO: registra -C por teste, simula compilação (BIN=) e execução (saída = entrada;
# nome com "wa" = saída errada; nome com "tle" = tempo 9 s).
CPUS=""; IN=""; OUT=""; TLOG=""; RW=""; SERR=""; BW=""
while (( $# )); do case "$1" in
  -C) CPUS="$2"; shift 2;; -i) IN="$2"; shift 2;; -o) OUT="$2"; shift 2;; -t) TLOG="$2"; shift 2;;
  -w) RW="$2"; shift 2;; -s) SERR="$2"; shift 2;; -B) BW="$2"; shift 2;;
  -T|-r|-d|-R|-M|-b|-S|-U) shift 2;; *) shift;; esac; done
[[ -n "$BW" ]] && : > "$BW"; [[ -n "$SERR" ]] && : > "$SERR"
if [[ -n "$RW" && -z "$IN" ]]; then echo "BIN=sol" > "$OUT"; : > "$TLOG"; exit 0; fi
name="$(basename "$IN")"
echo "start $(date +%s%N) $name cpus=${CPUS:-none}" >> "$FAKE_LOG"
sleep "${FAKE_SLEEP:-0.25}"
real=0.05; [[ "$name" == *tle* ]] && real=9
if [[ "$name" == *wa* ]]; then echo errado > "$OUT"; else cat "$IN" > "$OUT"; fi
printf 'real %s\nuser 0\nsys 0\nres 100\ncpu 99%%\n' "$real" > "$TLOG"
echo "end $(date +%s%N) $name" >> "$FAKE_LOG"
exit 0
EOF
chmod +x "$H/cage-run.sh"
mkdir -p "$W/bin"; printf '#!/bin/bash\necho "${FAKE_NPROC:-8}"\n' > "$W/bin/nproc"; chmod +x "$W/bin/nproc"
export PATH="$W/bin:$PATH" FAKE_LOG="$W/cage.log"

# ---- pacote sintético: 6 testes (t2wa e t5tle opcionais), saída = entrada ----------------------
mkpkg(){ # <conf-texto> [nomes de teste…]
  P="$W/pkg"; rm -rf "$P"; mkdir -p "$P/tests/input" "$P/tests/output"
  # ULIMITS[-u] do dev = o teto duro: o b-a-t aplica `ulimit -u` em si mesmo e o default (1024) é
  # menor que o nº de processos de uma sessão de desenvolvimento (fork: Resource temporarily unavailable)
  printf 'ULIMITS[-u]=%s\n%s\n' "$(ulimit -Hu)" "$1" > "$P/conf"; shift
  local t; for t in "$@"; do printf '%s\n' "$t" > "$P/tests/input/$t"; cp "$P/tests/input/$t" "$P/tests/output/$t"; done
  printf 'TL[c]=1\nTL[default]=1\n' > "$P/tl"
  printf 'int main(){return 0;}\n' > "$W/sol.c"
  : > "$FAKE_LOG"
}
run(){ # [env…] -> OUT (stdout inteiro), WB (workdir), VER (última linha), TRACE
  OUT="$(cd "$H" && env "$@" bash build-and-test.sh c "$W/sol.c" "$P" y 2>/dev/null)"
  WB="$(head -n1 <<<"$OUT")"; VER="$(tail -n1 <<<"$OUT")"; TRACE="$WB/run-trace.log"; DBG="$VER"
}
starts(){ grep -c '^start ' "$FAKE_LOG"; }
maxpar(){ # maior nº de execuções simultâneas (pelos carimbos start/end)
  awk '$1=="start"{print $2" +1"} $1=="end"{print $2" -1"}' "$FAKE_LOG" | sort -n \
    | awk '{c+=$2; if(c>m)m=c} END{print m+0}'; }

echo "== P workers pinados nos grupos (env do agente vence tudo) =="
mkpkg $'CPUNEEDED=2\nALLOWPARALLELTEST=n' t1 t2 t3 t4 t5 t6
run MOJ_TEST_CPUS=2 MOJ_PARALLEL=3 MOJ_CPU_GROUPS='0,1|2,3|4,5' MOJ_RELEASE_FILE="$W/rel"
ck "veredicto Accepted"                              '[[ "$VER" == Accepted* ]]'
ck "6 testes, cada um UMA vez"                       '[[ "$(starts)" == 6 && "$(grep -c "start .* t3 " "$FAKE_LOG")" == 1 ]]'
DBG="$(cat "$FAKE_LOG")"
ck "3 ao mesmo tempo (o conf dizia n: a env vence)"  '[[ "$(maxpar)" == 3 ]]'
ck "cada jaula pinada num grupo (-C)"                '! grep -q "cpus=none" "$FAKE_LOG" && grep -q "cpus=0,1" "$FAKE_LOG" && grep -q "cpus=2,3" "$FAKE_LOG" && grep -q "cpus=4,5" "$FAKE_LOG"'
ck "trace diz o paralelismo do agente"               'grep -q "NPROC: 3 (CPUs por teste: 2)" "$TRACE"'
DBG="$(cat "$W/rel")"
ck "cauda: grupos 1 e 2 liberados, o 0 nunca"        '[[ "$(sort -u "$W/rel" | tr "\n" " ")" == "1 2 " ]]'
ck "binfile.sh leva MOJ_TEST_CPUS e OMP_NUM_THREADS" 'grep -q "^export MOJ_TEST_CPUS=2$" "$WB/cagefiles/binfile.sh" && grep -q "^export OMP_NUM_THREADS=2$" "$WB/cagefiles/binfile.sh"'
ck "report.env: NPROCINFO=3 CPUNEEDEDINFO=2"         'grep -q "^NPROCINFO=3$" "$WB/report.env" && grep -q "^CPUNEEDEDINFO=2$" "$WB/report.env"'
ck "report.html: 3 teste(s) × 2 CPU(s)"              'grep -q "3 teste(s) ao mesmo tempo × 2 CPU(s) por teste" "$WB/report.html"'
ck "MAXPARALLELTESTS não passa dos grupos dados"     '[[ "$(maxpar)" -le 3 ]]'

echo "== rerun serial de TLE: libera os grupos ≥1 ANTES e roda no grupo 0 =="
mkpkg 'CPUNEEDED=1' t1 t2 t3tle t4
run MOJ_TEST_CPUS=1 MOJ_PARALLEL=2 MOJ_CPU_GROUPS='0|1' MOJ_RELEASE_FILE="$W/rel2"
ck "TLE confirmado no rerun"                         '[[ "$VER" == "Time Limit Exceeded"* ]]'
ck "t3tle rodou 2× (pool + rerun)"                   '[[ "$(grep -c "start .* t3tle " "$FAKE_LOG")" == 2 ]]'
ck "o rerun foi no grupo 0"                          '[[ "$(grep "start .* t3tle " "$FAKE_LOG" | tail -1)" == *"cpus=0" ]]'
ck "grupo 1 liberado (uma vez basta; repetição é ok)" 'grep -qx 1 "$W/rel2" && ! grep -qx 0 "$W/rel2"'

echo "== STOPWHEN visto por TODO worker =="
mkpkg $'STOPWHEN_WA=y' t1 t2wa t3 t4 t5 t6 t7 t8
run MOJ_PARALLEL=2 MOJ_CPU_GROUPS='0|1'
ck "Wrong Answer"                                    '[[ "$VER" == "Wrong Answer"* ]]'
DBG="$(cat "$FAKE_LOG")"
ck "parou: bem menos que 8 testes rodaram"           '[[ "$(starts)" -lt 8 ]]'
ck "…e o flag .stop existe no workdir"               '[[ -e "$WB/.stop" ]]'

echo "== sem env (local / agente antigo): P = min(nproc/k, MAXPARALLELTESTS) =="
mkpkg 'CPUNEEDED=2' t1 t2 t3 t4 t5 t6
FAKE_NPROC=8 run
ck "nproc=8, k=2 ⇒ NPROC 4"                          'grep -q "NPROC: 4 (CPUs por teste: 2)" "$TRACE"'
ck "sem pin (cpus=none)"                             '! grep -qv "cpus=none" <(grep "^start" "$FAKE_LOG")'
ck "no máximo 4 ao mesmo tempo"                      '[[ "$(maxpar)" -le 4 && "$(maxpar)" -ge 2 ]]'
mkpkg $'CPUNEEDED=2\nMAXPARALLELTESTS=3' t1 t2 t3 t4 t5 t6
FAKE_NPROC=8 run
ck "MAXPARALLELTESTS=3 é teto"                       'grep -q "NPROC: 3 " "$TRACE"'
mkpkg $'CPUNEEDED=2\nMAXPARALLELTESTS=30' t1 t2
FAKE_NPROC=8 run
ck "MAXPARALLELTESTS maior que nproc/k NÃO sobe (era sem teto)" 'grep -q "NPROC: 4 " "$TRACE"'
mkpkg $'ALLOWPARALLELTEST=n' t1 t2 t3
FAKE_NPROC=8 run
ck "ALLOWPARALLELTEST=n ⇒ 1"                         'grep -q "NPROC: 1 " "$TRACE" && [[ "$(maxpar)" == 1 ]]'
mkpkg 'CPUNEEDED=16' t1 t2
FAKE_NPROC=8 run
ck "nproc < CPUNEEDED: 1 worker + AVISO"             'grep -q "NPROC: 1 (CPUs por teste: 16)" "$TRACE" && grep -q "AVISO: CPUNEEDED=16" "$TRACE"'
mkpkg 'CPUNEEDED=abc' t1
FAKE_NPROC=8 run
ck "CPUNEEDED inválido cai em 1"                     'grep -q "CPUs por teste: 1)" "$TRACE" && grep -q "^export MOJ_TEST_CPUS=1$" "$WB/cagefiles/binfile.sh"'
mkpkg '' t1 t2 t3
FAKE_NPROC=2 run
ck "conf sem nada: NPROC = nproc (2), k = 1"         'grep -q "NPROC: 2 (CPUs por teste: 1)" "$TRACE"'
ck "report antigo: só \"N teste(s) ao mesmo tempo\"" 'grep -q "2 teste(s) ao mesmo tempo × 1 CPU(s) por teste" "$WB/report.html"'

echo "== calibreitor: sempre um teste por vez (MOJ_PARALLEL=1) =="
ck "calibreitor exporta MOJ_PARALLEL=1"              'grep -q "^export MOJ_PARALLEL=1" "$MT/calibreitor.sh"'
mkpkg $'ALLOWPARALLELTEST=y\nMAXPARALLELTESTS=8' t1 t2 t3 t4
FAKE_NPROC=8 run MOJ_PARALLEL=1
ck "com MOJ_PARALLEL=1 o conf não abre paralelo"     'grep -q "NPROC: 1 " "$TRACE" && [[ "$(maxpar)" == 1 ]]'

echo "== cage-run.sh -C e templates =="
ck "cage-run aceita -C (usage + getopt + PIN antes do bwrap)" 'grep -q "^-C, --cpus" "$MT/cage-run.sh" && grep -q "cpus:" "$MT/cage-run.sh" && grep -q "\$SHIELD \$PIN \$SCOPE bwrap" "$MT/cage-run.sh"'
for t in paralelo-openmp paralelo-mpi; do
  ck "template $t: json válido com slots"            'jq -e ".slots|length>0" "$MT/script-templates/$t/template.json" >/dev/null'
  ck "template $t: scripts com +x e sintaxe"         'for f in $(find "$MT/script-templates/$t/files" -name "*.sh"); do [[ -x "$f" ]] && bash -n "$f" || exit 1; done'
done
ck "MPI run.sh usa -np \$MOJ_TEST_CPUS e pipefail"   'grep -q -- "-np \"\${MOJ_TEST_CPUS:-1}\"" "$MT/script-templates/paralelo-mpi/files/c/run.sh" && grep -q "set -o pipefail" "$MT/script-templates/paralelo-mpi/files/c/run.sh"'
ck "OpenMP compile com -fopenmp"                     'grep -q -- "-fopenmp" "$MT/script-templates/paralelo-openmp/files/c/compile.sh" && grep -q -- "-fopenmp" "$MT/script-templates/paralelo-openmp/files/cpp/compile.sh"'
if command -v gcc >/dev/null 2>&1 && gcc -fopenmp -x c -o "$W/omp" - <<<'#include <omp.h>
#include <stdio.h>
int main(){int n=0;
#pragma omp parallel
{
#pragma omp atomic
n++;}
printf("%d\n",n);return 0;}' 2>/dev/null; then
  ck "OpenMP obedece OMP_NUM_THREADS (o canal da jaula)" '[[ "$(OMP_NUM_THREADS=3 "$W/omp")" == 3 ]]'
else echo "  (sem gcc -fopenmp aqui: pulei a prova do OMP_NUM_THREADS)"; fi

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
