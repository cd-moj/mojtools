#!/bin/bash
# test-tl-methods.sh — a faixa dos parâmetros do Kattis (`_tlm_in`, tl-methods.sh) funciona SEM bc (27/10/2026).
# A conferência do pacote (validate-problem.sh, conf_tlmethod_sane) roda no SERVIDOR, cuja imagem não tem bc: com o
# `bc -l` no caminho a saída vinha vazia e TODO KATTIS_* explícito virava "valor inválido", até inteiro — o problema
# ficava "pacote: COM ERRO" (fotos-do-drone, com o a=2.5 que o próprio `moj calib` sugeriu). Prende:
#   · as faixas e os limites (fechado embaixo; aberto embaixo com `x`; fechado em cima) com PATH só com o awk;
#   · o lixo recusado pelo formato (tl_num) antes de qualquer conta;
#   · a MESMA resposta do `_num_in` da CLI (moj-cli/moj), quando o checkout irmão existe.
# Sem jaula, sem rede. `make test-tl-methods`.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; pass=$((pass+1)); else echo "  FAIL: $1"; fail=$((fail+1)); fi; }
# PATH só com o awk: sem bc (nem nada além dos builtins do bash)
mkdir -p "$W/bin"; ln -s "$(command -v awk)" "$W/bin/awk"
run(){ PATH="$W/bin" "$BASH" -c 'source "$1"; shift; _tlm_in "$@"' _ "$MT/tl-methods.sh" "$@"; }
ck "o PATH do teste não tem bc"                 '! PATH="$W/bin" command -v bc >/dev/null'
ck "2.5 em [1,100] (o a que o moj calib sugeriu)" 'run 2.5 1 100'
ck "2 em [1,100] (inteiro também era recusado)"  'run 2 1 100'
ck "1 e 100: a faixa é fechada"                  'run 1 1 100 && run 100 1 100'
ck "0.99 e 101 fora de [1,100]"                  '! run 0.99 1 100 && ! run 101 1 100'
ck "0.5, .5 e 10 em (0,10]"                       'run 0.5 0 10 x && run .5 0 10 x && run 10 0 10 x'
ck "0 fora de (0,10]: aberto embaixo com x"      '! run 0 0 10 x'
ck "lixo recusado pelo formato"                  '! run "2,5" 1 100 && ! run 1e2 1 100 && ! run "" 1 100 && ! run "-1" 0 10 x && ! run " 2" 1 100'
# a mesma regra do _num_in da CLI, valor a valor (só com o checkout irmão)
CLI="$MT/../moj-cli/moj"
if [[ -f "$CLI" ]]; then
  src="$(sed -n '/^_num_in(){/,/; }$/p' "$CLI")"
  if [[ -n "$src" ]]; then
    eval "$src"; source "$MT/tl-methods.sh"; diffs=""
    for c in "2.5 1 100" "2 1 100" "1 1 100" "100 1 100" "0.99 1 100" "101 1 100" "0.5 0 10 x" ".5 0 10 x" "0 0 10 x" "10 0 10 x" "10.01 0 10 x" "2,5 1 100" "1e2 1 100"; do
      read -r v lo hi x <<<"$c"; a=0; b=0
      _tlm_in "$v" "$lo" "$hi" "${x:-}" && a=1; _num_in "$v" "$lo" "$hi" "${x:-}" && b=1
      [[ $a == "$b" ]] || diffs+="[$c: mojtools=$a cli=$b] "
    done
    ck "a mesma resposta do _num_in da CLI (13 casos)" '[[ -z "$diffs" ]]'
    [[ -z "$diffs" ]] || echo "    $diffs"
  else ck "achei o _num_in da CLI" 'false'; fi
else echo "  (sem o checkout irmão do moj-cli: a paridade com o _num_in fica de fora)"; fi
echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
