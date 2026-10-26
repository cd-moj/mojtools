#!/bin/bash
# test-calib-methods.sh — os DOIS métodos de TL (tl-methods.sh; cdmoj/docs/PACOTE.md "Métodos de TL"), 26/10/2026.
# Pedido do Ribas: o método do Kattis (spec 2025-09) first class ao lado do MOJ; a calibração grava SEMPRE os dois
# e o conf (TLMETHOD) escolhe. Roda o calibreitor.sh + build-and-test.sh REAIS numa cópia do mojtools com um
# cage-run.sh FALSO: o tempo de cada teste sai de uma linha `TIMES <padrão> [<teste>=<s>…]` na FONTE da solução
# (WRONG <teste> = saída errada), o fake respeita o teto -T (teste morto = tempo do teto) e REGISTRA o -T. Prende:
#   · a tabela com as duas metades (TL[] MOJ intocado; TLKATTIS[] por linguagem; default = o menor) e o
#     `declare -A` dentro dela — o parser do agente VELHO (copiado) a lê sem morrer;
#   · o arredondamento do Kattis (tl_kattis) e os parâmetros inválidos caindo no padrão;
#   · pass/slow/wrong julgadas pelos dois métodos: `code_alt`/`tl_alt` (compare tardio: TLE no MOJ e AC no Kattis),
#     um item por teste mesmo com o rerun de TLE, `method`/`etl` na linha;
#   · o piso de tempo só em calibração (b × TL Kattis, teto 30 s), sem mudar o veredicto ativo;
#   · o julgamento de job: MOJ_TL_METHOD (o job) › TLMETHOD (conf); TLOVERRIDE vence; tabela sem TLKATTIS cai no
#     MOJ e diz (report.env); nenhum log.verdictalt fora da calibração;
#   · tl-checksum: TLMETHOD fora dos dois carimbos; KATTIS_* dentro.
# Sem jaula, sem rede, sem sleep. `make test-calib`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:400}"; ((fail++)); fi; }
num_eq(){ [[ "$(echo "($1) - ($2) < 0.0001 && ($2) - ($1) < 0.0001" | bc -l)" == 1 ]]; }

H="$W/mt"; mkdir -p "$H"
cp "$MT"/{calibreitor.sh,build-and-test.sh,tl-methods.sh,lang-canon.sh,gen-report.sh,score-summary.sh,tl-checksum.sh} "$H"/
cp -r "$MT/lang" "$H/lang"
cat > "$H/cage-run.sh" <<'EOF'
#!/bin/bash
# cage-run FALSO: compilação = BIN=sol; execução = o tempo da linha TIMES da fonte, morto no teto -T
IN=""; OUT=""; TLOG=""; RW=""; SERR=""; BW=""; D=""; T=""
while (( $# )); do case "$1" in
  -i) IN="$2"; shift 2;; -o) OUT="$2"; shift 2;; -t) TLOG="$2"; shift 2;; -w) RW="$2"; shift 2;;
  -s) SERR="$2"; shift 2;; -B) BW="$2"; shift 2;; -d) D="$2"; shift 2;; -T) T="$2"; shift 2;;
  -r|-R|-M|-b|-S|-U|-C) shift 2;; *) shift;; esac; done
[[ -n "$BW" ]] && : > "$BW"; [[ -n "$SERR" ]] && : > "$SERR"
if [[ -n "$RW" && -z "$IN" ]]; then echo "BIN=sol" > "$OUT"; : > "$TLOG"; exit 0; fi
name="$(basename "$IN")"
spec="$(grep -h -m1 -o 'TIMES .*' "$D"/* 2>/dev/null | head -1)"; wrong="$(grep -h -m1 -o 'WRONG .*' "$D"/* 2>/dev/null | head -1)"
read -r _ real rest <<<"$spec"; real="${real:-0.05}"
for kv in $rest; do [[ "${kv%%=*}" == "$name" ]] && real="${kv#*=}"; done
src="$(grep -l -m1 'TIMES' "$D"/* 2>/dev/null | head -1)"
echo "run $(basename "${src:-?}") $name T=$T" >> "$FAKE_LOG"
rc=0
if [[ "$(echo "$real > $T" | bc -l)" == 1 ]]; then real="$T"; rc=137; : > "$OUT"   # morto no teto
elif [[ " ${wrong#WRONG } " == *" $name "* ]]; then echo errado > "$OUT"
else cat "$IN" > "$OUT"; fi
printf 'real %s\nuser 0\nsys 0\nres 100\ncpu 99%%\n' "$real" > "$TLOG"
exit $rc
EOF
chmod +x "$H/cage-run.sh"
export FAKE_LOG="$W/cage.log" HOSTNAME=juizteste
unset MOJ_TL_METHOD MOJ_CALIBRATING MOJ_CALIB_ALT MOJ_TLFILE MOJ_PROBLEM_ID CAGE_ROOT MOJ_PARALLEL

# pacote: 3 testes; good em C (pior 0,21 s no big3) e em py (pior 1,30 s); lentas, pass e wrong
P="$W/repo/pp"; mkdir -p "$P/tests/input" "$P/tests/output" "$P"/sols/{good,slow,pass,wrong}
for t in sample1 t2 big3; do echo "$t" > "$P/tests/input/$t"; cp "$P/tests/input/$t" "$P/tests/output/$t"; done
mkconf(){ printf 'ULIMITS[-u]=%s\n%s' "$(ulimit -Hu)" "${1:-}" > "$P/conf"; }
printf '// TIMES 0.10 big3=0.21\nint main(){}\n' > "$P/sols/good/a.c"
printf '# TIMES 0.50 big3=1.30\n' > "$P/sols/good/b.py"
printf '// TIMES 0.10 big3=9\n' > "$P/sols/slow/s.c"          # lenta de verdade nos dois métodos
printf '// TIMES 0.10 big3=0.6\n' > "$P/sols/slow/m.c"        # TLE no MOJ (0,3035 s), AC no Kattis (1 s)
printf '# TIMES 0.10 big3=20\n' > "$P/sols/slow/sp.py"        # piso: b × TL Kattis do py (3 s) = 4,5 s
printf '// TIMES 0.10 big3=0.5\n' > "$P/sols/pass/p.c"        # passa no Kattis, não no MOJ
printf '// TIMES 0.10\n// WRONG t2\n' > "$P/sols/wrong/w.c"

calib(){ rm -f "$FAKE_LOG"; ( cd "$W" && bash "$H/calibreitor.sh" "$P" > "$W/calib.out" 2>&1 ); }
row(){ jq -c --arg f "$1" '.[] | select(.file == $f)' "$P/.calib-sols.json"; }
tst(){ jq -c --arg f "$1" --arg t "$2" '.[] | select(.file == $f) | .tests[] | select(.name == $t)' "$P/.calib-sols.json"; }

echo "== calibração (método moj, o padrão) =="
mkconf ''
calib
TLF="$P/tl.juizteste"
DBG="$(cat "$TLF" 2>&1) $(tail -5 "$W/calib.out")"
ck "tl.<host> publicado" '[[ -s "$TLF" && -s "$P/tl" ]]'
v(){ ( declare -A TL TLKATTIS; source "$TLF"; eval "printf %s \"\${$1[$2]:-}\"" ); }
ck "MOJ intocado: TL[c] = 1,35 × 0,21 + 0,02" 'num_eq "$(v TL c)" 0.3035'
ck "MOJ: TL[py] = 1,35 × 1,30 + 0,02; default = o menor" 'num_eq "$(v TL py)" 1.775 && num_eq "$(v TL default)" 0.3035'
ck "Kattis por linguagem: c ⌈0,42⌉ = 1, py ⌈2,6⌉ = 3, default = 1" '[[ "$(v TLKATTIS c)" == 1 && "$(v TLKATTIS py)" == 3 && "$(v TLKATTIS default)" == 1 ]]'
ck "o declare -A vai dentro da tabela" 'grep -q "^declare -A TLKATTIS$" "$TLF"'
ck "o log mostra a conta do Kattis" 'grep -q "Kattis: py 2.0 × 1.30 = 2.6 → 3 s" "$W/calib.out"'
# o parser do agente do juiz de ANTES desta mudança (moj-agent.sh tl_to_json), sob set -u
old_agent(){ ( set -u; declare -A TL TLMOD; source "$1" 2>/dev/null
  for k in "${!TL[@]}"; do printf '%s\t%s\n' "$k" "${TL[$k]}"; done ) \
  | jq -R -s -c 'split("\n")|map(select(length>0)|split("\t")|{(.[0]):.[1]})|add // {}'; }
DBG="$(old_agent "$TLF")"
ck "agente velho lê a tabela nova: só o TL[], sem morrer" '[[ "$(jq -r "keys|join(\",\")" <<<"$DBG")" == "c,default,py" ]]'

echo "== pass/slow/wrong pelos dois métodos =="
DBG="$(row s.c)"
ck "s.c: method moj, etl = o ETL de sempre (2,5035)" '[[ "$(jq -r .method <<<"$DBG")" == moj ]] && num_eq "$(jq -r .etl <<<"$DBG")" 2.5035'
DBG="$(tst s.c big3)"
ck "s.c big3: TLE nos dois (tl 0,3035 · tl_alt 1)" '[[ "$(jq -r .code <<<"$DBG")" == TLE && "$(jq -r .code_alt <<<"$DBG")" == TLE ]] && num_eq "$(jq -r .tl <<<"$DBG")" 0.3035 && [[ "$(jq -r .tl_alt <<<"$DBG")" == 1 ]]'
ck "s.c: UM item por teste, mesmo com o rerun de TLE" '[[ "$(jq -r --arg f s.c "[.[]|select(.file==\$f)|.tests[]|select(.name==\"big3\")]|length" "$P/.calib-sols.json")" == 1 ]]'
DBG="$(tst m.c big3)"
ck "m.c big3: TLE no MOJ, AC no Kattis (compare tardio)" '[[ "$(jq -r .code <<<"$DBG")" == TLE && "$(jq -r .code_alt <<<"$DBG")" == AC ]]'
DBG="$(tst p.c big3)"
ck "p.c (pass) big3: TLE no MOJ, AC no Kattis" '[[ "$(jq -r .code <<<"$DBG")" == TLE && "$(jq -r .code_alt <<<"$DBG")" == AC ]]'
DBG="$(tst w.c t2)"
ck "w.c (wrong) t2: WA nos dois" '[[ "$(jq -r .code <<<"$DBG")" == WA && "$(jq -r .code_alt <<<"$DBG")" == WA ]]'
DBG="$(row sp.py) | $(grep ' sp.py ' "$FAKE_LOG" | sort -u)"
ck "sp.py: piso = b × TL Kattis do py + 0,5 = 5 s (o ETL do MOJ seria 3,975)" 'num_eq "$(jq -r .etl <<<"$(row sp.py)")" 5 && grep -q "run sp.py big3 T=5" "$FAKE_LOG"'
ck "sp.py big3: morto em 5 s ≥ 1,5 × 3 (a margem do Kattis é medível)" 'num_eq "$(jq -r .time <<<"$(tst sp.py big3)")" 5'
DBG="$(row a.c)"
ck "good: sem code_alt (TL fictício de 5 s), method gravado" '[[ "$(jq -r "[.tests[]|has(\"code_alt\")]|any" <<<"$DBG")" == false && "$(jq -r .method <<<"$DBG")" == moj ]]'
ck "o log diz o veredicto pelo outro método" 'grep -q "Pelo método kattis (TL 1s): AC 3" "$W/calib.out"'
# o compare tardio (só p/ o outro método) vai p/ -log.compare-alt: o report.html mostra o -log.compare, e um diff
# num teste que pelo método ativo deu TLE confundiria o autor
( cd "$H" && MOJ_CALIBRATING=1 MOJ_CALIB_ALT=1 MOJ_TLFILE="$P/tl.juizteste" bash build-and-test.sh c "$P/sols/slow/m.c" "$P" y 2>/dev/null ) > "$W/bat.out"
WB="$(head -1 "$W/bat.out")"
DBG="$(ls "$WB" | grep -i compare | paste -sd' ')"
ck "compare tardio em -log.compare-alt, nunca no -log.compare do teste TLE" '[[ -s "$WB/big3-log.compare-alt" || -e "$WB/big3-log.compare-alt" ]] && [[ ! -e "$WB/big3-log.compare" ]]'

echo "== TLMETHOD=kattis no conf =="
mkconf 'TLMETHOD=kattis'
calib
DBG="$(row m.c)"
ck "m.c: method kattis; big3 AC (TL 1) e TLE pelo MOJ" '[[ "$(jq -r .method <<<"$DBG")" == kattis && "$(jq -r .code <<<"$(tst m.c big3)")" == AC && "$(jq -r .code_alt <<<"$(tst m.c big3)")" == TLE ]]'
ck "a tabela é a mesma (as duas metades sempre)" '[[ "$(v TLKATTIS py)" == 3 ]] && num_eq "$(v TL c)" 0.3035'
DBG="$(row s.c)"
ck "s.c sob Kattis: ETL = 2 + 1 + 0,2" 'num_eq "$(jq -r .etl <<<"$DBG")" 3.2'
ck "good sob kattis: sem aviso de tabela sem TLKATTIS" '! grep -rq "não tem TLKATTIS" "$W/calib.out"'

echo "== parâmetros do Kattis e teto de 30 s =="
mkconf $'KATTIS_AC_TO_TIME_LIMIT=1.5\nKATTIS_TIME_RESOLUTION=0.5\nKATTIS_TIME_LIMIT_TO_TLE=20'
calib
ck "a=1,5 r=0,5: c ⌈0,315/0,5⌉×0,5 = 0,5; py ⌈1,95/0,5⌉×0,5 = 2" '[[ "$(v TLKATTIS c)" == 0.5 && "$(v TLKATTIS py)" == 2 ]]'
ck "b=20: o piso do sp.py para no teto de 30 s" 'grep -q "run sp.py big3 T=30" "$FAKE_LOG"'
mkconf $'KATTIS_AC_TO_TIME_LIMIT=abc\nKATTIS_TIME_RESOLUTION=0'
calib
ck "parâmetro inválido cai no padrão (com aviso)" '[[ "$(v TLKATTIS py)" == 3 ]] && grep -q "AVISO: KATTIS_AC_TO_TIME_LIMIT=abc" "$W/calib.out"'

echo "== julgamento de job (fora da calibração) =="
mkconf ''; calib                                     # a tabela das duas metades em tl.juizteste
bat(){ rm -f "$FAKE_LOG"; ( cd "$H" && env "$@" bash build-and-test.sh c "$P/sols/slow/m.c" "$P" 2>/dev/null ) > "$W/bat.out"
  WB="$(head -1 "$W/bat.out")"; FIN="$(tail -1 "$W/bat.out")"; }
renv(){ grep -m1 "^$1=" "$WB/report.env" | cut -d= -f2-; }
bat MOJ_TL_METHOD=kattis
DBG="$FIN $(renv TL_METHOD) $(renv TL_LANG)"
ck "MOJ_TL_METHOD=kattis (o job): m.c Accepted com TL 1" '[[ "$FIN" == Accepted* && "$(renv TL_METHOD)" == kattis && "$(renv TL_LANG)" == 1 ]]'
ck "job: nenhum log.verdictalt e o ETL de sempre (2 + 1 + 0,2)" '[[ ! -e "$WB/log.verdictalt" ]] && grep -q "T=3.2" "$FAKE_LOG"'
bat
ck "sem env e conf sem TLMETHOD: MOJ, m.c TLE" '[[ "$FIN" == "Time Limit Exceeded"* && "$(renv TL_METHOD)" == moj ]]'
mkconf 'TLMETHOD=kattis'; bat
ck "TLMETHOD=kattis no conf (sem env): Accepted" '[[ "$FIN" == Accepted* ]]'
bat MOJ_TL_METHOD=moj
ck "o job vence o conf: MOJ_TL_METHOD=moj dá TLE" '[[ "$FIN" == "Time Limit Exceeded"* ]]'
mkconf $'TLMETHOD=kattis\nTLOVERRIDE[default]=0.5'; bat
ck "TLOVERRIDE vence o método: 0,6 s > 0,5 s = TLE" '[[ "$FIN" == "Time Limit Exceeded"* && "$(renv TL_LANG)" == 0.5 ]]'
mkconf 'TLMETHOD=kattis'; grep -v TLKATTIS "$TLF" > "$W/t" && cp "$W/t" "$TLF"; bat
DBG="$FIN $(renv TL_METHOD) $(renv TL_METHOD_WANTED)"
ck "tabela sem TLKATTIS: cai no MOJ e diz no report.env" '[[ "$FIN" == "Time Limit Exceeded"* && "$(renv TL_METHOD)" == moj && "$(renv TL_METHOD_WANTED)" == kattis ]]'

echo "== tl-checksum =="
cks(){ bash "$H/tl-checksum.sh" "$@" "$P"; }
printf 'CALIBRATIONTL=5' > "$P/conf"; n0="$(cks)"; a0="$(cks --all-sols)"
{ printf 'TLMETHOD=kattis\n'; printf 'CALIBRATIONTL=5'; } > "$P/conf"
ck "TLMETHOD no começo, conf sem \\n final: os dois carimbos iguais" '[[ "$(cks)" == "$n0" && "$(cks --all-sols)" == "$a0" ]]'
printf 'CALIBRATIONTL=5\nTLMETHOD="moj"\n' > "$P/conf"; printf 'CALIBRATIONTL=5\n' > "$W/c0"
cp "$P/conf" "$W/c1"; cp "$W/c0" "$P/conf"; n1="$(cks)"; cp "$W/c1" "$P/conf"
ck "TLMETHOD no fim (conf com \\n): igual ao conf sem a linha" '[[ "$(cks)" == "$n1" ]]'
printf 'CALIBRATIONTL=5\nKATTIS_TIME_RESOLUTION=0.5\n' > "$P/conf"
ck "KATTIS_* mudam os dois carimbos" '[[ "$(cks)" != "$n1" && "$(cks --all-sols)" != "$a0" ]]'

echo "== validate-problem: conf_tlmethod_sane =="
export CONTESTSDIR="$W/c" RUNDIR="$W/run"; mkdir -p "$CONTESTSDIR/treino/var/jsons" "$RUNDIR"
Q="$W/repo/qq"; mkdir -p "$Q/docs" "$Q/tests/input" "$Q/tests/output" "$Q/sols/good"
printf 'Some.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$Q/docs/enunciado.md"
echo 1 > "$Q/tests/input/sample1"; echo 1 > "$Q/tests/output/sample1"; echo autor > "$Q/author"; echo 'int main(){}' > "$Q/sols/good/a.c"
val(){ printf 'CALIBRATIONTL=5\n%s\n' "$1" > "$Q/conf"; rm -f "$RUNDIR"/validation/*.json
  bash "$MT/validate-problem.sh" "$Q" >/dev/null 2>&1
  DBG="$(jq -c '.checks[]|select(.name=="conf_tlmethod_sane")' "$RUNDIR"/validation/*.json 2>&1)"; }
val ''; ck "sem as chaves: ok (moj)" '[[ "$(jq -r .ok <<<"$DBG")" == true ]]'
val $'TLMETHOD=kattis\nKATTIS_AC_TO_TIME_LIMIT=2.5\nKATTIS_TIME_LIMIT_TO_TLE="1.5"\nKATTIS_TIME_RESOLUTION=0.1'
ck "kattis com parâmetros válidos: ok" '[[ "$(jq -r .ok <<<"$DBG")" == true ]]'
for bad in 'TLMETHOD=Kattis' 'TLMETHOD=boca' 'KATTIS_AC_TO_TIME_LIMIT=0.5' 'KATTIS_TIME_LIMIT_TO_TLE=abc' 'KATTIS_TIME_RESOLUTION=0' 'KATTIS_TIME_RESOLUTION=11'; do
  val "$bad"; ck "reprova $bad" '[[ "$(jq -r .ok <<<"$DBG")" == false ]]'
done

echo "== a calibração nunca libera grupo de CPU (26/10/2026) =="
# a calibração disparada por um JOB de 2 grupos herdava o arquivo de liberação dele: cada build-and-test filho
# anotava o grupo 1 como livre e o agente o devolvia ao escalonador com o job ainda julgando nele
mkconf ''
REL="$W/released"; : > "$REL"
( export MOJ_RELEASE_FILE="$REL" MOJ_CPU_GROUPS="0|0"; calib )
DBG="$(cat "$REL") | $(tail -3 "$W/calib.out")"
ck "com o MOJ_RELEASE_FILE do job no ambiente, nenhum grupo anotado" '[[ -s "$P/tl.juizteste" && ! -s "$REL" ]]'

echo "calib-methods: $pass ok, $fail falhas"; [[ $fail -eq 0 ]]
