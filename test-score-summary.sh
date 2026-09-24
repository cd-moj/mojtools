#!/bin/bash
# test-score-summary.sh — o VEREDICTO de problema pontuado por GRUPOS (tests/score + score-summary.sh).
#
# Relato do Ribas (24/09/2026): o score-summary.sh declarava "Wrong Answer" (e FINALRESP "Wrong,<n>p")
# sempre que um grupo falhava — mesmo quando o teste tinha dado TLE, RE ou MLE: o aluno lia "resposta
# errada" num estouro de tempo/crash/memória. Agora os grupos decidem só a NOTA e o veredicto é o mesmo
# que os testes dariam sem grupos (o pior teste). Pacote quebrado vira Judge Error, nunca culpa do aluno.
#
# Roda o build-and-test.sh REAL (com o score-summary.sh e o gen-report.sh reais) numa cópia do mojtools
# com um cage-run.sh FALSO que decide o desfecho pelo NOME do teste:
#   xwa = saída errada (WA pelo lang/compare.sh) · xtle = real 9 s (TLE; o rerun segue TLE)
#   xrte = exit 139 (RE) · xnz = exit 1 (RE_NZEC) · xmle = RSS enorme (MLE, com MEMLIMITMB no conf)
# Sem jaula, sem rede. `make test-score`.
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
name="$(basename "$IN")"; real=0.05; res=100; rc=0
[[ "$name" == *xtle* ]] && real=9
[[ "$name" == *xmle* ]] && res=999999
[[ "$name" == *xrte* ]] && rc=139
[[ "$name" == *xnz* ]] && rc=1
if [[ "$name" == *xwa* ]]; then echo errado > "$OUT"; else cat "$IN" > "$OUT"; fi
printf 'real %s\nuser 0\nsys 0\nres %s\ncpu 99%%\n' "$real" "$res" > "$TLOG"
exit $rc
EOF
chmod +x "$H/cage-run.sh"

# pacote: <tests/score (texto; vazio = sem tests/score)> <conf extra> <testes…>
mkpkg(){
  P="$W/pkg"; rm -rf "$P"; mkdir -p "$P/tests/input" "$P/tests/output"
  # ULIMITS[-u] do dev = o teto duro (o b-a-t aplica `ulimit -u` em si mesmo; o default 1024 é menor
  # que os processos de uma sessão de desenvolvimento)
  printf 'ULIMITS[-u]=%s\n%s\n' "$(ulimit -Hu)" "$2" > "$P/conf"
  [[ -n "$1" ]] && printf '%s\n' "$1" > "$P/tests/score"
  shift 2
  local t; for t in "$@"; do printf '%s\n' "$t" > "$P/tests/input/$t"; cp "$P/tests/input/$t" "$P/tests/output/$t"; done
  printf 'TL[c]=1\nTL[default]=1\n' > "$P/tl"
  printf 'int main(){return 0;}\n' > "$W/sol.c"
}
# julga e expõe: FIN (última linha do stdout = FINALRESP), WB (workdir) e as chaves do report.env
run(){
  local out; out="$(cd "$H" && bash build-and-test.sh c "$W/sol.c" "$P" y 2>/dev/null)"
  WB="$(head -n1 <<<"$out")"; FIN="$(tail -n1 <<<"$out")"
  VC=""; SC=""; SM=""; SK=""; SG=""; SR=""
  if [[ -f "$WB/report.env" ]]; then
    eval "$( source "$WB/report.env"
      printf 'VC=%q SC=%q SM=%q SK=%q SG=%q SR=%q\n' "$VERDICT_CANON" "$SCORE" "$SCORE_MAX" "$SCORE_KIND" "$SCORE_GROUPS" "$SMALLRESP" )"
  fi
  DBG="FIN=$FIN | VC=$VC SC=$SC SM=$SM SR=$SR SG=$SG"
}
pts(){ grep -oE '[0-9]+p' <<<"$FIN" | head -1 | tr -d p; }   # a nota como o servidor a lê (1º NNp)
banner(){ grep -o '<span class="big">[^<]*</span>' "$WB/report.html" | head -1 | sed 's/<[^>]*>//g'; }
invariants(){ # o que TODO caso tem de cumprir
  ck "  · a nota da string (1º NNp) = SCORE"                  '[[ "$(pts)" == "$SC" ]]'
  ck "  · o prefixo da string É o VERDICT_CANON"              '[[ "$FIN" == "$VC,"* ]]'
  ck "  · nunca \"Accepted\" com nota abaixo do máximo"       '[[ "$VC" != Accepted || "$SC" == "$SM" ]]'
  ck "  · nunca o \"Wrong,\" legado"                          '[[ "$FIN" != Wrong,* ]]'
  ck "  · banner do report.html = VERDICT_CANON"              '[[ "$(banner)" == "$VC" ]]'
}
SCORE3=$'sample* - 0 pontos\ng1_* - 30 pontos\ng2_* - 70 pontos'

echo "== todos os grupos aceitos =="
mkpkg "$SCORE3" "" sample1 g1_a1 g1_a2 g2_b1 g2_b2; run
ck "Accepted,100p"                                   '[[ "$VC" == Accepted && "$FIN" == "Accepted,100p. Pontos | 30 | 70 |" ]]'
ck "SCORE 100/100, points, grupos [30/30, 70/70]"    '[[ "$SC/$SM/$SK" == 100/100/points && "$(jq -c "[.[]|.earned]" <<<"$SG")" == "[30,70]" ]]'
invariants

echo "== grupo com WA: Wrong Answer (o rótulo canônico, não o \"Wrong\" legado) =="
mkpkg "$SCORE3" "" sample1 g1_a1 g2_b1 g2_xwa1; run
ck "Wrong Answer,30p"                                '[[ "$VC" == "Wrong Answer" && "$FIN" == "Wrong Answer,30p. Pontos | 30 | 0 | quantitativos"* ]]'
ck "grupos [30/30, 0/70]"                            '[[ "$(jq -c "[.[]|.earned]" <<<"$SG")" == "[30,0]" ]]'
invariants

echo "== grupo com TLE: Time Limit Exceeded (era \"Wrong Answer\" — o relato) =="
mkpkg "$SCORE3" "" sample1 g1_a1 g2_b1 g2_xtle1; run
ck "Time Limit Exceeded,30p"                         '[[ "$VC" == "Time Limit Exceeded" && "$FIN" == "Time Limit Exceeded,30p. Pontos | 30 | 0 |"* ]]'
ck "quantitativos traz o TLE"                        '[[ "$FIN" == *"TLE(1)"* ]]'
ck "SMALLRESP=TLE (a cor do banner bate com o texto)" '[[ "$SR" == TLE ]]'
invariants

echo "== WA e TLE: vale o pior (TLE), como sem grupos =="
mkpkg "$SCORE3" "" sample1 g1_xwa1 g2_xtle1; run
ck "Time Limit Exceeded,0p"                          '[[ "$VC" == "Time Limit Exceeded" && "$FIN" == "Time Limit Exceeded,0p."* && "$SC" == 0 ]]'
invariants

echo "== RE (sinal) e RE_NZEC: Runtime Error, sem a vírgula de \"Possible Runtime Error, non-zero return\" =="
mkpkg "$SCORE3" "" sample1 g1_a1 g2_xrte1; run
ck "RE: Runtime Error,30p"                           '[[ "$VC" == "Runtime Error" && "$FIN" == "Runtime Error,30p."* && "$SR" == RE ]]'
invariants
mkpkg "$SCORE3" "" sample1 g1_a1 g2_xnz1; run
ck "RE_NZEC: Runtime Error,30p"                      '[[ "$VC" == "Runtime Error" && "$FIN" == "Runtime Error,30p."* && "$SR" == RE_NZEC ]]'
invariants

echo "== MLE: Memory Limit Exceeded (e a barra do report aparece) =="
mkpkg "$SCORE3" "MEMLIMITMB=256" sample1 g1_a1 g2_xmle1; run
ck "Memory Limit Exceeded,30p"                       '[[ "$VC" == "Memory Limit Exceeded" && "$FIN" == "Memory Limit Exceeded,30p."* && "$SR" == MLE ]]'
ck "barra de distribuição com MLE (faltava)"        'grep -q "hbar-label\">Memory Limit Exceeded<" "$WB/report.html"'
ck "legenda do mapa com MLE"                         'grep -q "</span>Memory Limit Exceeded</span>" "$WB/report.html"'
invariants

echo "== exemplo (peso 0) com TLE e o resto aceito: TLE com a nota cheia =="
mkpkg "$SCORE3" "" samplextle1 g1_a1 g2_b1; run
ck "Time Limit Exceeded,100p (não aceito: o exemplo falhou)" '[[ "$VC" == "Time Limit Exceeded" && "$FIN" == "Time Limit Exceeded,100p."* && "$SC" == 100 ]]'
invariants

echo "== grupo de peso 0 SEM teste (ex.: SAMPLE=no): vácuo, não derruba =="
mkpkg $'sample* - 0 pontos\ng1_* - 100 pontos' "SAMPLE=no" g1_a1 g1_a2; run
ck "Accepted,100p (antes: Wrong,100p)"               '[[ "$VC" == Accepted && "$FIN" == "Accepted,100p. Pontos | 100 |" ]]'
invariants

echo "== pacote quebrado: Judge Error, nota 0 — nunca culpa do aluno =="
mkpkg $'g1_* - 100 pontos' "" g1_a1 extra1; run
ck "teste sem grupo: Judge Error,0p com o motivo"    '[[ "$VC" == "Judge Error" && "$FIN" == "Judge Error,0p. teste '"'"'extra1'"'"' sem grupo em tests/score (erro do pacote)" && "$SC" == 0 ]]'
ck "…banner cinza (SMALLRESP=UE), não verde"         '[[ "$SR" == UE ]] && grep -q "class=\"banner gray\"" "$WB/report.html"'
invariants
mkpkg $'g1_* - 30 pontos\ng9_* - 70 pontos' "" g1_a1 g1_a2; run
ck "grupo de peso>0 sem teste, tudo AC: Judge Error,0p (nunca Accepted)" '[[ "$VC" == "Judge Error" && "$FIN" == "Judge Error,0p. grupo sem teste em tests/score (erro do pacote). Pontos | 30 | -1 |"* && "$SC" == 0 ]]'
invariants
mkpkg $'g1_* - 30 pontos\ng2_* - 40 pontos\ng9_* - 30 pontos' "" g1_a1 g2_xtle1; run
ck "…mas com um TLE de verdade vale o TLE (a falha é do aluno)" '[[ "$VC" == "Time Limit Exceeded" && "$FIN" == "Time Limit Exceeded,30p."* ]]'
invariants

echo "== sem tests/score: o caminho de sempre (nada mudou) =="
mkpkg "" "" t1 t2 t3xtle t4; run
ck "Time Limit Exceeded,75p, SCORE_KIND=tests"       '[[ "$FIN" == "Time Limit Exceeded,75p" && "$VC" == "Time Limit Exceeded" && "$SK" == tests ]]'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
