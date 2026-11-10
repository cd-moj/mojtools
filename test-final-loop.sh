#!/bin/bash
# test-final-loop.sh — o LAÇO FINAL do build-and-test.sh depois do pool paralelo (26/10/2026).
#
# O pool para (`.stop`) no 1º teste que dispara a regra de parada (STOPWHEN_* do conf, ou qualquer falha com
# RUNALL≠y). O laço final reroda o TLE em série; quando o rerun dá AC, a parada era ESPÚRIA. Antes, os testes
# que ela deixou de fora viravam "INPUT NOT TESTED": o veredicto saía "Unknown ERROR" e, com grupos
# (tests/score), um "Accepted" FALSO (grupo com 1 AC executado e o resto sem rodar pontuava). E o
# `((RESPERRO++)) && continue` não pulava quando RESPERRO era 0: linha EXECTIME vazia e contagem dupla.
# Agora a regra de parada é reaplicada em ordem sobre os veredictos FINAIS, e o teste que o pool não rodou
# roda no laço final, em série, enquanto nada confirmado a disparou.
#
# Roda o build-and-test.sh REAL (com score-summary.sh e gen-report.sh reais) numa cópia do mojtools com um
# cage-run.sh FALSO que decide pelo NOME do teste:
#   xtle = real 9 s (TLE LONGE do TL de 1 s, sempre) · xslow = real 1,5 s (TLE PERTO, sempre) · xflk = 1,3 s só na 1ª
#   execução, AC depois (o teste "instável", a interferência) · xwa = WA
# Cada execução é anotada em $RUNLOG. Sem jaula, sem rede. `make test-final-loop`.
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
name="$(basename "$IN")"; real=0.05
echo "$name" >> "$RUNLOG"
[[ "$name" == *xtle* ]] && real=9
[[ "$name" == *xslow* ]] && real=1.5
if [[ "$name" == *xflk* && ! -e "$FLAKY/$name" ]]; then : > "$FLAKY/$name"; real=1.3; fi
if [[ "$name" == *xfar* && ! -e "$FLAKY/$name" ]]; then : > "$FLAKY/$name"; real=2.5; fi   # 2,5× o TL de 1 s, só na 1ª
if [[ "$name" == *xjit* ]]; then if [[ ! -e "$FLAKY/$name" ]]; then : > "$FLAKY/$name"; real=0.08; else real=0.01; fi; fi  # soluço de 80 ms na 1ª, 10 ms depois
if [[ "$name" == *xwa* ]]; then echo errado > "$OUT"; else cat "$IN" > "$OUT"; fi
printf 'real %s\nuser 0\nsys 0\nres 100\ncpu 99%%\n' "$real" > "$TLOG"
exit 0
EOF
chmod +x "$H/cage-run.sh"
export RUNLOG="$W/runs" FLAKY="$W/flaky"

# pacote: <tests/score (vazio = sem)> <conf extra> <testes…>
mkpkg(){
  P="$W/pkg"; rm -rf "$P" "$FLAKY"; mkdir -p "$P/tests/input" "$P/tests/output" "$FLAKY"; : > "$RUNLOG"
  printf 'ULIMITS[-u]=%s\n%s\n' "$(ulimit -Hu)" "$2" > "$P/conf"
  [[ -n "$1" ]] && printf '%s\n' "$1" > "$P/tests/score"
  shift 2
  local t; for t in "$@"; do printf '%s\n' "$t" > "$P/tests/input/$t"; cp "$P/tests/input/$t" "$P/tests/output/$t"; done
  printf 'TL[c]=1\nTL[default]=1\n' > "$P/tl"
  printf 'int main(){return 0;}\n' > "$W/sol.c"
}
# run <runall> [env…]: o pool em SÉRIE (MOJ_PARALLEL=1) torna a parada determinística
run(){
  local ra="$1"; shift
  local out; out="$(cd "$H" && env MOJ_PARALLEL=1 "$@" bash build-and-test.sh c "$W/sol.c" "$P" "$ra" 2>/dev/null)"
  WB="$(head -n1 <<<"$out")"; FIN="$(tail -n1 <<<"$out")"; TR="$WB/run-trace.log"
  VC=""; SC=""; SR=""; VR=""; FF=""
  [[ -f "$WB/report.env" ]] && eval "$( source "$WB/report.env"; printf 'VC=%q SC=%q SR=%q VR=%q FF=%q\n' "$VERDICT_CANON" "$SCORE" "$SMALLRESP" "${VERDICT_RULE:-}" "${FIRST_FAIL:-}" )"
  DBG="FIN=$FIN | VC=$VC SC=$SC SR=$SR | runs: $(tr '\n' ' ' < "$RUNLOG")"
}
runs(){ grep -cx "$1" "$RUNLOG"; }
clean_trace(){ ! grep -qE '^EXECTIME [^ ]+ *$' "$TR" && ! grep -q 'bad array subscript' "$TR"; }

echo "== parada ESPÚRIA (TLE que passa no rerun), sem grupos: a cauda roda, Accepted =="
mkpkg "" "STOPWHEN_TLE=y" t1 t2xflk t3 t4
run y
ck "Accepted,100p (era Unknown ERROR)"                '[[ "$FIN" == "Accepted,100p" && "$SR" == AC ]]'
ck "t2xflk: pool + rerun; t3 e t4: UMA vez cada"     '[[ "$(runs t2xflk)" == 2 && "$(runs t3)" == 1 && "$(runs t4)" == 1 ]]'
ck "o trace diz que a cauda rodou em série"           'grep -q "running it now, serially" "$TR"'
ck "EXECTIME com tempo para todos os testes"          '[[ "$(grep -cE "^EXECTIME t[0-9a-z]+ [0-9.]+ AC" "$TR")" == 4 ]] && clean_trace'

echo "== parada ESPÚRIA com GRUPOS: nada de \"Accepted\" falso — a cauda roda e o Accepted é de verdade =="
mkpkg $'sample* - 0 pontos\ng1_* - 30 pontos\ng2_* - 70 pontos' "STOPWHEN_TLE=y" sample1 g1_a1 g2_a_xflk1 g2_b2 g2_b3
run y
ck "Accepted,100p com todos os testes rodados"       '[[ "$FIN" == "Accepted,100p. Pontos | 30 | 70 |" && "$VC" == Accepted ]]'
ck "g2_b2, g2_b3 e sample1 rodaram (antes: nunca)"   '[[ "$(runs g2_b2)" == 1 && "$(runs g2_b3)" == 1 && "$(runs sample1)" == 1 ]]'

echo "== parada CONFIRMADA (STOPWHEN_TLE): a cauda NÃO roda; sem linha vazia nem contagem dupla =="
mkpkg "" "STOPWHEN_TLE=y" t1 t2xtle t3 t4
run y
ck "Time Limit Exceeded"                              '[[ "$FIN" == "Time Limit Exceeded,25p" && "$SR" == TLE ]]'
ck "t3 e t4 nunca rodaram; t2xtle (LONGE): sem rerun" '[[ "$(runs t3)" == 0 && "$(runs t4)" == 0 && "$(runs t2xtle)" == 1 ]]'
ck "o trace diz por que não rodaram"                  '[[ "$(grep -c "not run: a previous test stopped the run" "$TR")" == 2 ]]'
ck "sem EXECTIME vazio e sem bad array subscript"     'clean_trace'

echo "== parada CONFIRMADA com grupos: grupo com teste que não rodou NÃO pontua =="
# grupo X = t1 e t3 (t3 vem depois do TLE confirmado e não roda); grupo Y = o t2xtle
mkpkg $'t1, t3 - 50 pontos\nt2* - 50 pontos' "STOPWHEN_TLE=y" t1 t2xtle t3
run y
ck "Time Limit Exceeded,0p (antes: 50p — o grupo de t1/t3 pontuava sem o t3)" '[[ "$FIN" == "Time Limit Exceeded,0p."* && "$SC" == 0 && "$VC" == "Time Limit Exceeded" ]]'
ck "t3 não rodou"                                     '[[ "$(runs t3)" == 0 ]]'

echo "== WA confirmado (STOPWHEN_WA): sem rerun, a cauda não roda =="
mkpkg "" "STOPWHEN_WA=y" t1 t2xwa t3
run y
ck "Wrong Answer; t3 nunca rodou"                     '[[ "$FIN" == "Wrong Answer,33p" && "$(runs t3)" == 0 && "$(runs t2xwa)" == 1 ]]'

echo "== RUNALL≠y (a fase good da calibração): parada espúria → a cauda roda e entra no pior tempo =="
mkpkg "" "" t1 t2xflk t3 t4
run n
ck "Accepted,100p"                                    '[[ "$FIN" == "Accepted,100p" ]]'
ck "t3 e t4 rodaram uma vez e têm EXECTIME com tempo" '[[ "$(runs t3)" == 1 && "$(runs t4)" == 1 ]] && grep -qE "^EXECTIME t3 0.05 AC" "$TR" && grep -qE "^EXECTIME t4 0.05 AC" "$TR"'
mkpkg "" "" t1 t2xtle t3
run n
ck "RUNALL≠y com TLE confirmado: a cauda não roda"   '[[ "$FIN" == "Time Limit Exceeded,33p" && "$(runs t3)" == 0 ]] && clean_trace'

echo "== RERUN SÓ DO TLE PERTO DO TL (10/11/2026: TLERERUN_BAND, padrão 2×) =="
mkpkg "" "" t1 t2xslow t3xslow t4
run y
ck "TLE perto confirmado: rerun UMA vez, o 2º perto não repete" '[[ "$SR" == TLE && "$(runs t2xslow)" == 2 && "$(runs t3xslow)" == 1 ]]'
ck "o trace diz por que repetiu"                      'grep -q "Rerun: because got TLE near the time limit (within 2.0x)" "$TR"'
mkpkg "" "" t1 t2xtle t3xflk
run y
ck "TLE longe não repete e NÃO gasta o rerun: o instável depois passa" '[[ "$(runs t2xtle)" == 1 && "$(runs t3xflk)" == 2 ]] && grep -q "EXECTIME t3xflk 0.05 AC" "$TR"'
ck "o trace diz que o longe não repetiu"              'grep -q "Rerun: not needed — this TLE is far from the time limit" "$TR"'
mkpkg "" "" t1 t2xfar
run y
ck "2,5 s com TL de 1 s (além de 2× e do piso de TL+1 s): longe, TLE" '[[ "$SR" == TLE && "$(runs t2xfar)" == 1 ]]'
mkpkg "" "TLERERUN_BAND=3" t1 t2xfar
run y
ck "TLERERUN_BAND=3 no conf: o de 2,5 s fica perto e passa" '[[ "$SR" == AC && "$(runs t2xfar)" == 2 ]]'
mkpkg "" "TLERERUN_BAND=1.5" t1 t2xfar
run y MOJ_TLE_RERUN_BAND=3
ck "MOJ_TLE_RERUN_BAND vence o conf"                  '[[ "$SR" == AC && "$(runs t2xfar)" == 2 ]]'
mkpkg "" "TLERERUN_BAND=abc" t1 t2xfar
run y
ck "banda inválida = 2,0"                             '[[ "$SR" == TLE && "$(runs t2xfar)" == 1 ]] && clean_trace'
# o caso da revisão: o TL mínimo da calibração (0,0335 s, metade dos TLs de C/C++) e um soluço de 80 ms
mkpkg "" "" t2xjit; printf 'TL[c]=.0335\nTL[default]=.0335\n' > "$P/tl"
run y
ck "TL de 0,0335 s com soluço de 80 ms: o piso de TL+1 s repete e passa" '[[ "$SR" == AC && "$(runs t2xjit)" == 2 ]]'
mkpkg "" "" t1 t2xtle; printf 'TL[c]=3\nTL[default]=3\n' > "$P/tl"
run y
ck "laço infinito com TL de 3 s (morto no teto, ETL ≤ 2×TL): não repete" '[[ "$SR" == TLE && "$(runs t2xtle)" == 1 ]]'

echo "== REGRA DO VEREDICTO (MOJ_VERDICT_RULE, opção do contest): worst × first =="
mkpkg "" "" t1 t2xwa t3xtle
run y
ck "sem a regra = o mais grave (TLE), como sempre"   '[[ "$SR" == TLE && "$VR" == worst ]]'
run y MOJ_VERDICT_RULE=first
ck "first = o do 1º que falhou (WA do t2)"            '[[ "$FIN" == "Wrong Answer,33p" && "$SR" == WA && "$VR" == first && "$FF" == t2xwa ]]'
ck "o trace diz qual seria o mais grave"              'grep -q "Verdict rule first: WA (test t2xwa) instead of the most severe, TLE" "$TR"'
ck "o report diz o teste"                             'grep -q "veredicto do 1º teste que falhou: t2xwa" "$WB/report.html"'
mkpkg "" "" a1xtle sample1xwa
run y MOJ_VERDICT_RULE=first
ck "os EXEMPLOS vêm primeiro (sample1 antes de a1)"   '[[ "$SR" == WA && "$FF" == sample1xwa ]]'
ck "e rodam primeiro"                                 '[[ "$(head -n1 "$RUNLOG")" == sample1xwa ]]'
mkpkg "" "" t2xwa t10xtle
run y MOJ_VERDICT_RULE=first
ck "ordem NATURAL do nome (t2 antes de t10)"          '[[ "$SR" == WA && "$FF" == t2xwa ]]'
mkpkg "" "STOPWHEN_TLE=y" t1 t2xtle t10xwa
run y MOJ_VERDICT_RULE=first
ck "com STOPWHEN: para no 1º (TLE), t10 nem roda"     '[[ "$SR" == TLE && "$FF" == t2xtle && "$(runs t10xwa)" == 0 ]] && clean_trace'
mkpkg "" "" t1 t2
run y MOJ_VERDICT_RULE=first
ck "tudo certo continua Accepted"                     '[[ "$FIN" == "Accepted,100p" && -z "$FF" ]]'
mkpkg $'g1_* - 40 pontos\ng2_* - 60 pontos' "" g1_a g2_axtle g2_bxwa
run y MOJ_VERDICT_RULE=first
ck "com grupos: a nota é a mesma, o veredicto é o 1º" '[[ "$VC" == "Time Limit Exceeded" && "$SC" == 40 && "$FF" == g2_axtle ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
