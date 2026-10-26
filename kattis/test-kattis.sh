#!/bin/bash
# kattis/test-kattis.sh — o TEMPO na ida e volta MOJ ⇄ Kattis (spec 2025-09), 26/10/2026 (cdmoj/docs/PACOTE.md
# "Métodos de TL"). Prende:
#   · export de um problema TLMETHOD=kattis: time_multipliers e time_resolution dos KATTIS_*, time_limit = o
#     TLOVERRIDE[default] (o TL fixado pelo autor; resolução fina quando ele não é múltiplo), `pass` num diretório
#     próprio com `permitted: [AC]` (sem use_for_time_limit; chave relativa a submissions/);
#   · export de um problema MOJ: o de sempre (calibrafactor como ac_to_time_limit);
#   · import de volta: TLMETHOD, KATTIS_* e TLOVERRIDE restaurados; pass volta p/ sols/pass;
#   · import de pacote NATIVO: TLMETHOD=kattis, multiplicadores (inclusive o legado time_multiplier/
#     time_safety_margin), time_limit -> TLOVERRIDE[default], brute_force -> upcoming (nunca pass);
#   · valor que não é número nunca vira linha do conf (o conf é sourced no juiz).
# Precisa de python3+pyyaml (pula sem eles). `make test-kattis`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null || { echo "kattis: python3+pyyaml ausentes — pulando"; exit 0; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: ${DBG:0:400}"; ((fail++)); fi; }
y(){ python3 -c 'import sys,yaml,json; print(json.dumps(yaml.safe_load(open(sys.argv[1]))))' "$1"; }

P="$W/repo/pp"; mkdir -p "$P/docs" "$P/tests/input" "$P/tests/output" "$P"/sols/{good,pass,slow}
printf 'Some.\n\n## Entrada\n\nx\n\n## Saída\n\ny\n' > "$P/docs/enunciado.md"
echo 1 > "$P/tests/input/sample1"; echo 1 > "$P/tests/output/sample1"; echo autor > "$P/author"
echo 'int main(){}' > "$P/sols/good/a.c"; echo 'print(1)' > "$P/sols/pass/b.py"; echo 'int main(){for(;;);}' > "$P/sols/slow/s.c"
cat > "$P/conf" <<'EOF'
TLMETHOD=kattis
KATTIS_AC_TO_TIME_LIMIT=3
KATTIS_TIME_RESOLUTION=0.5
TLOVERRIDE[default]=2.5
TLOVERRIDE[py]=7
ULIMITS[-u]=10000
EOF

echo "== export de um problema Kattis =="
bash "$MT/kattis/export.sh" "$P" "repo#pp" "$W/out" >/dev/null 2>&1
Y="$(y "$W/out/problem.yaml")"; DBG="$(jq -c .limits <<<"$Y")"
ck "time_multipliers.ac_to_time_limit = 3 (sem o time_limit_to_tle ausente)" '[[ "$(jq -c .limits.time_multipliers <<<"$Y")" == "{\"ac_to_time_limit\":3.0}" ]]'
ck "time_resolution 0,5 e time_limit 2,5 (múltiplo: a resolução fica)" '[[ "$(jq -r .limits.time_resolution <<<"$Y")" == 0.5 && "$(jq -r .limits.time_limit <<<"$Y")" == 2.5 ]]'
DBG="$(ls "$W/out/submissions" | paste -sd' ') | $(cat "$W/out/submissions/submissions.yaml" 2>&1)"
ck "pass num diretório próprio, regra permitted:[AC], chave sem o prefixo submissions/" '[[ -f "$W/out/submissions/pass/b.py" && "$(y "$W/out/submissions/submissions.yaml" | jq -c .)" == "{\"pass\":{\"permitted\":[\"AC\"]}}" ]]'
ck "o sidecar leva método, parâmetros e overrides" '[[ "$(jq -c "[.tl_method, .kattis.ac_to_time_limit, .tloverride.default]" "$W/out/.kattis.json")" == "[\"kattis\",\"3\",\"2.5\"]" ]]'
sed -i 's/^KATTIS_TIME_RESOLUTION=0.5/KATTIS_TIME_RESOLUTION=1/' "$P/conf"
bash "$MT/kattis/export.sh" "$P" "repo#pp" "$W/out1" >/dev/null 2>&1
DBG="$(y "$W/out1/problem.yaml" | jq -c .limits)"
ck "time_limit 2,5 com resolução 1: a resolução vira 0,01 (o TL do autor não muda)" '[[ "$(jq -r .time_resolution <<<"$DBG")" == 0.01 && "$(jq -r .time_limit <<<"$DBG")" == 2.5 ]]'

echo "== import de volta (ida e volta) =="
bash "$MT/kattis/import.sh" "$W/out" "$W/back" >/dev/null 2>&1
DBG="$(cat "$W/back/conf")"
ck "TLMETHOD=kattis e os KATTIS_* restaurados" 'grep -qx "TLMETHOD=kattis" "$W/back/conf" && grep -qx "KATTIS_AC_TO_TIME_LIMIT=3" "$W/back/conf" && grep -qx "KATTIS_TIME_RESOLUTION=0.5" "$W/back/conf"'
ck "TLOVERRIDE do autor restaurado (default e py)" 'grep -qx "TLOVERRIDE\[default\]=2.5" "$W/back/conf" && grep -qx "TLOVERRIDE\[py\]=7" "$W/back/conf"'
ck "pass volta p/ sols/pass" '[[ -f "$W/back/sols/pass/b.py" && -f "$W/back/sols/slow/s.c" && -f "$W/back/sols/good/a.c" ]]'

echo "== export de um problema MOJ (como sempre) =="
printf 'TLMOD[calibrafactor]=1.5\nULIMITS[-u]=10000\n' > "$P/conf"
bash "$MT/kattis/export.sh" "$P" "repo#pp" "$W/out2" >/dev/null 2>&1
DBG="$(y "$W/out2/problem.yaml" | jq -c .limits)"
ck "calibrafactor como ac_to_time_limit; sem time_limit" '[[ "$(jq -r .time_multipliers.ac_to_time_limit <<<"$DBG")" == 1.5 && "$(jq -r ".time_limit // \"-\"" <<<"$DBG")" == - ]]'
bash "$MT/kattis/import.sh" "$W/out2" "$W/back2" >/dev/null 2>&1
DBG="$(cat "$W/back2/conf")"
ck "ida e volta MOJ: sem TLMETHOD, calibrafactor do sidecar, sem KATTIS_*" '! grep -q "^TLMETHOD" "$W/back2/conf" && grep -qx "TLMOD\[calibrafactor\]=\"1.5\"" "$W/back2/conf" && ! grep -q "^KATTIS_" "$W/back2/conf"'

echo "== import de pacote nativo =="
N="$W/nat"; mkdir -p "$N/data/sample" "$N/submissions"/{accepted,brute_force,time_limit_exceeded} "$N/statement"
echo 1 > "$N/data/sample/1.in"; echo 1 > "$N/data/sample/1.ans"; printf 'x\n' > "$N/statement/problem.en.md"
echo 'int main(){}' > "$N/submissions/accepted/a.c"; echo 'x' > "$N/submissions/brute_force/bf.c"; echo 'y' > "$N/submissions/time_limit_exceeded/t.c"
cat > "$N/problem.yaml" <<'EOF'
problem_format_version: 2025-09
name: {en: Nativo}
limits:
  time_multipliers: {ac_to_time_limit: 2.5, time_limit_to_tle: 1.25}
  time_resolution: 0.25
  time_limit: 1.5
EOF
bash "$MT/kattis/import.sh" "$N" "$W/nb" >/dev/null 2>&1
DBG="$(cat "$W/nb/conf")"
ck "nativo: TLMETHOD=kattis + os três KATTIS_*" 'grep -qx TLMETHOD=kattis "$W/nb/conf" && grep -qx KATTIS_AC_TO_TIME_LIMIT=2.5 "$W/nb/conf" && grep -qx KATTIS_TIME_LIMIT_TO_TLE=1.25 "$W/nb/conf" && grep -qx KATTIS_TIME_RESOLUTION=0.25 "$W/nb/conf"'
ck "time_limit explícito -> TLOVERRIDE[default]; calibrafactor 1,35 (não o multiplicador)" 'grep -qx "TLOVERRIDE\[default\]=1.5" "$W/nb/conf" && grep -qx "TLMOD\[calibrafactor\]=1.35" "$W/nb/conf"'
ck "brute_force -> upcoming (nunca pass); TLE -> slow" '[[ -f "$W/nb/sols/upcoming/bf.c" && ! -d "$W/nb/sols/pass" && -f "$W/nb/sols/slow/t.c" ]]'
sed -i 's/^  time_multipliers.*/  time_multiplier: 5\n  time_safety_margin: 2/; /time_resolution/d; /time_limit:/d' "$N/problem.yaml"
bash "$MT/kattis/import.sh" "$N" "$W/nb2" >/dev/null 2>&1
DBG="$(cat "$W/nb2/conf")"
ck "legado time_multiplier/time_safety_margin -> KATTIS_*; sem time_limit, sem override" 'grep -qx KATTIS_AC_TO_TIME_LIMIT=5 "$W/nb2/conf" && grep -qx KATTIS_TIME_LIMIT_TO_TLE=2 "$W/nb2/conf" && ! grep -q TLOVERRIDE "$W/nb2/conf"'
cat > "$N/problem.yaml" <<'EOF'
problem_format_version: 2025-09
name: {en: Lixo}
limits:
  time_multipliers: {ac_to_time_limit: "$(touch x)", time_limit_to_tle: 0.5}
  time_resolution: 0
  time_limit: abc
EOF
bash "$MT/kattis/import.sh" "$N" "$W/nb3" >/dev/null 2>&1
DBG="$(cat "$W/nb3/conf")"
ck "valor que não é número (ou fora da faixa) não vira linha do conf" '! grep -qE "^(KATTIS_|TLOVERRIDE)" "$W/nb3/conf" && ! grep -q "touch" "$W/nb3/conf"'

echo "kattis: $pass ok, $fail falhas"; [[ $fail -eq 0 ]]
