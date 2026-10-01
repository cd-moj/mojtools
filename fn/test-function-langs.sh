#!/bin/bash
# test-function-langs.sh — FUNCTION_LANGS no conf (submissão de função, cdmoj/docs/PACOTE.md):
#   • tl-checksum.sh ignora a linha (sozinha e junto do SAMPLE), byte a byte;
#   • gen-problem-json.sh serve `function_langs` canônico (py3 → py, cc → cpp), [] sem a linha;
#   • validate-problem.sh: conf_function_sane reprova linguagem sem scripts/<lang>/compile.sh e id
#     inválido; avisa driver fora da lista (render_warnings);
#   • fn/driver-langs.sh: main num heredoc = driver; ban/OpenMP (programa completo) não;
#   • fn/install-fn.sh grava a linha (união, só as linguagens pedidas ou já declaradas), sem conf também.
# Sem jaula e sem rede (o validate defere as soluções; o gen-problem-json usa o pandoc se houver).
# `make test-fn`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:-}"; ((fail++)); fi; }
export CONTESTSDIR="$W/c" RUNDIR="$W/run"; mkdir -p "$CONTESTSDIR/treino/var/jsons" "$RUNDIR"

# pacote mínimo: enunciado + exemplo + um driver C (main num heredoc) + um ban em C++ (sem main)
P="$W/repo/pp"; mkdir -p "$P/docs" "$P/tests/input" "$P/tests/output" "$P/scripts/c" "$P/scripts/cpp" "$P/scripts/py3"
printf '%% Soma\n\nSome.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$P/docs/enunciado.md"
echo 1 > "$P/tests/input/sample1"; echo 1 > "$P/tests/output/sample1"; echo autor > "$P/author"
cat > "$P/scripts/c/compile.sh" <<'EOS'
#!/bin/bash
cat > /tmp/rwdir/__judge_main.c <<'EOF'
int soma(int a, int b);
int main(void){ return 0; }
EOF
make
EOS
printf '#!/bin/bash\n# programa completo + ban de string.h\ngrep -q strlen *.cpp && exit 1\nmake\n' > "$P/scripts/cpp/compile.sh"
printf '#!/bin/bash\ncat > drv.py <<EOF\nif __name__ == "__main__":\n    print(1)\nEOF\n' > "$P/scripts/py3/compile.sh"
chmod +x "$P"/scripts/*/compile.sh
printf 'CALIBRATIONTL=5' > "$P/conf"   # sem \n final de propósito

echo "== tl-checksum ignora a linha =="
base="$(bash "$MT/tl-checksum.sh" "$P")"
{ printf 'FUNCTION_LANGS=c,py\n'; cat "$P/conf"; } > "$W/c1"; cp "$P/conf" "$W/conf0"; cp "$W/c1" "$P/conf"
DBG="$(bash "$MT/tl-checksum.sh" "$P") × $base"
ck "com FUNCTION_LANGS no começo: mesmo hash" '[[ "$(bash "$MT/tl-checksum.sh" "$P")" == "$base" ]]'
{ printf 'SAMPLE=no\nFUNCTION_LANGS="c"\n'; cat "$W/conf0"; } > "$P/conf"
ck "junto do SAMPLE: mesmo hash" '[[ "$(bash "$MT/tl-checksum.sh" "$P")" == "$base" ]]'
printf 'CALIBRATIONTL=6' > "$P/conf"
ck "o resto do conf continua contando" '[[ "$(bash "$MT/tl-checksum.sh" "$P")" != "$base" ]]'

echo "== gen-problem-json serve function_langs =="
gj(){ printf 'CALIBRATIONTL=5\n%s\n' "$1" > "$P/conf"; bash "$MT/gen-problem-json.sh" "$P" >/dev/null 2>&1
  DBG="$(jq -c .function_langs "$CONTESTSDIR/treino/var/jsons-private/repo#pp.json" 2>&1)"; }
gj 'FUNCTION_LANGS="c, py3 ,cc"'; ck "canônico e ordenado: [c,cpp,py]" '[[ "$DBG" == "[\"c\",\"cpp\",\"py\"]" ]]'
gj 'FUNCTION_LANGS=c # comentário'; ck "comentário fora: [c]" '[[ "$DBG" == "[\"c\"]" ]]'
gj '# sem a linha'; ck "sem a linha: []" '[[ "$DBG" == "[]" ]]'
gj 'FUNCTION_LANGS=*'; ck "glob não expande: []" '[[ "$DBG" == "[]" ]]'

echo "== driver-langs (a heurística) =="
DBG="$(bash "$MT/fn/driver-langs.sh" "$P" | paste -sd,)"
ck "main em heredoc = driver (c, py3 → py); ban em C++ não" '[[ "$DBG" == "c,py" ]]'

echo "== validate-problem: conf_function_sane =="
val(){ printf 'CALIBRATIONTL=5\n%s\n' "$1" > "$P/conf"; rm -f "$RUNDIR"/validation/*.json
  bash "$MT/validate-problem.sh" "$P" >/dev/null 2>&1
  DBG="$(jq -c '[(.checks[]|select(.name=="conf_function_sane")|.ok), .render_warnings]' "$RUNDIR"/validation/*.json 2>&1)"; }
val 'FUNCTION_LANGS=c,py'
ck "c,py com driver: ok e sem aviso de driver" '[[ "$DBG" == "[true,"* && "$DBG" != *driver-de-funcao* ]]'
val 'FUNCTION_LANGS=c'
ck "py fora da lista: ok com aviso" '[[ "$DBG" == "[true,"* && "$DBG" == *"driver-de-funcao-fora-do-FUNCTION_LANGS(py)"* ]]'
val 'FUNCTION_LANGS=c,java'
ck "java sem compile.sh: reprova" '[[ "$DBG" == "[false,"* ]]'
val 'FUNCTION_LANGS=c,x$y'
ck "id inválido: reprova" '[[ "$DBG" == "[false,"* ]]'
val ''
ck "sem a linha: ok e avisa os dois drivers" '[[ "$DBG" == "[true,"* && "$DBG" == *"(c,py)"* ]]'

echo "== install-fn grava a linha =="
Q="$W/q"; mkdir -p "$Q/scripts/cpp"; printf '#!/bin/bash\nmake\n' > "$Q/scripts/cpp/compile.sh"; printf 'CALIBRATIONTL=5' > "$Q/conf"
bash "$MT/fn/install-fn.sh" "$Q" --langs "c py" >/dev/null 2>&1
DBG="$(head -1 "$Q/conf")"
ck "c,py no começo; o ban em C++ fica fora" '[[ "$DBG" == "FUNCTION_LANGS=c,py" ]]'
ck "o resto do conf intacto, byte a byte" 'cmp -s <(sed 1d "$Q/conf") <(printf "CALIBRATIONTL=5")'
bash "$MT/fn/install-fn.sh" "$Q" --langs "java" >/dev/null 2>&1
DBG="$(grep FUNCTION_LANGS "$Q/conf" | paste -sd'|')"
ck "2ª instalação: união numa linha só" '[[ "$DBG" == "FUNCTION_LANGS=c,py,java" ]]'
R="$W/r"; mkdir -p "$R"
( cd "$W" && touch zz && bash "$MT/fn/install-fn.sh" "$R" --langs "rs" >/dev/null 2>&1 )
DBG="$(cat "$R/conf" 2>&1)"
ck "pacote sem conf: cria com a linha" '[[ "$DBG" == "FUNCTION_LANGS=rs" ]]'

echo; echo "RESULT: $pass passed, $fail failed"; exit $(( fail > 0 ? 1 : 0 ))
