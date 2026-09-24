#!/bin/bash
# test-validator.sh — o validador de entrada (testlib/validator-run.sh + install-validator.sh) e a regra do
# tl-checksum para scripts/validator.cpp. Precisa de g++ e jq (sem g++: pula). `make test-validator`.
#   · sem validador = none; tudo certo = ok; entrada fora do limite = invalid com a mensagem da testlib;
#   · validador que não compila = error (e a mensagem do g++); laço infinito = FAIL por entrada (VALIDATOR_TL)
#     e o ORÇAMENTO total corta o resto (um validador ruim não pode comer o teto da calibração);
#   · install-validator.sh sai 0/1/2;
#   · tl-checksum: o estreito ignora scripts/validator.cpp, o --all-sols não.
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"; MT="$(cd "$HERE/.." && pwd)"
command -v g++ >/dev/null 2>&1 || { echo "test-validator: sem g++ — pulando"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
P="$W/p"; mkdir -p "$P/scripts" "$P/tests/input" "$P/tests/output" "$P/sols/good"
printf '2\n3 4\n' > "$P/tests/input/sample1"; printf '3\n1 2 3\n' > "$P/tests/input/t1"; printf '7\n' > "$P/tests/output/sample1"
printf 'int main(){}\n' > "$P/sols/good/a.cpp"; printf 'TLMOD[calibrafactor]=1.35\n' > "$P/conf"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${J:0:300}"; ((fail++)); fi; }
run(){ J="$(bash "$HERE/validator-run.sh" "$P" 2>&1)"; }

run
ck "sem validador: verdict none, sem testes"        '[[ "$(jq -r .verdict <<<"$J")" == none && "$(jq -r ".tests|length" <<<"$J")" == 0 ]]'
ck "…e a linha é uma entrada de .calib-sols.json"   '[[ "$(jq -c "[.category,.file,.lang]" <<<"$J")" == "[\"validator\",\"scripts/validator.cpp\",\"cpp\"]" ]]'
cp "$MT/script-templates/validator-testlib/files/validator.cpp" "$P/scripts/validator.cpp"
run
ck "template: todas as entradas passam"             '[[ "$(jq -r .verdict <<<"$J")" == ok && "$(jq -c "[.tests[].code]" <<<"$J")" == "[\"OK\",\"OK\"]" ]]'
printf '1296\n' > "$P/tests/input/t2"; printf '1\n5' > "$P/tests/input/t3"
run
ck "N fora do limite = INVALID com a mensagem"      '[[ "$(jq -r .verdict <<<"$J")" == invalid && "$(jq -r ".tests[]|select(.name==\"t2\")|.msg" <<<"$J")" == *"1296"*"[1, 1000]"* ]]'
ck "sem \\n no fim = INVALID (Expected EOLN)"        '[[ "$(jq -r ".tests[]|select(.name==\"t3\")|.code" <<<"$J")" == INVALID && "$(jq -r ".tests[]|select(.name==\"t3\")|.msg" <<<"$J")" == *EOLN* ]]'
ck "binário em cache fora de scripts/"              'ls "$P/.validator-cache"/validator.* >/dev/null 2>&1 && ! ls "$P/scripts" | grep -qv "^validator.cpp$"'
bash "$HERE/install-validator.sh" "$P" >/dev/null 2>&1; rc=$?
ck "install-validator: sai 1 com entrada inválida"  '[[ $rc == 1 ]]'
rm -f "$P/tests/input/t2" "$P/tests/input/t3"
bash "$HERE/install-validator.sh" "$P" >/dev/null 2>&1; rc=$?
ck "install-validator: sai 0 com tudo certo"        '[[ $rc == 0 ]]'
a="$(bash "$MT/tl-checksum.sh" "$P")"; aa="$(bash "$MT/tl-checksum.sh" --all-sols "$P")"
printf '// outro\n' >> "$P/scripts/validator.cpp"
ck "tl-checksum estreito ignora o validador"        '[[ "$(bash "$MT/tl-checksum.sh" "$P")" == "$a" ]]'
ck "…a versão do pacote (--all-sols) não"           '[[ "$(bash "$MT/tl-checksum.sh" --all-sols "$P")" != "$aa" ]]'
printf 'int main( {\n' > "$P/scripts/validator.cpp"
run
ck "não compila = error com a mensagem do g++"      '[[ "$(jq -r .verdict <<<"$J")" == error && "$(jq -r ".tests[0].msg" <<<"$J")" == "não compilou:"*error* ]]'
bash "$HERE/install-validator.sh" "$P" >/dev/null 2>&1; rc=$?
ck "install-validator: sai 2 quando não roda"       '[[ $rc == 2 ]]'
printf '#include "testlib.h"\nint main(int c,char**v){registerValidation(c,v);volatile long x=0;for(;;)x++;}\n' > "$P/scripts/validator.cpp"
VALIDATOR_BUDGET=120 bash "$HERE/validator-run.sh" "$P" >/dev/null 2>&1   # aquece o cache (compila)
for i in 4 5 6 7; do printf '1\n1\n' > "$P/tests/input/t$i"; done   # entradas de sobra p/ o orçamento cortar
J="$(VALIDATOR_TL=1 VALIDATOR_BUDGET=2 bash "$HERE/validator-run.sh" "$P" 2>&1)"
ck "laço infinito: FAIL por tempo na 1ª entrada"    '[[ "$(jq -r ".tests[0].code" <<<"$J")" == FAIL && "$(jq -r ".tests[0].msg" <<<"$J")" == *"passou de 1s"* ]]'
ck "…o orçamento corta o resto (error)"             '[[ "$(jq -r .verdict <<<"$J")" == error && "$(jq -r ".tests[-1].msg" <<<"$J")" == *"orçamento"* ]]'
echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
