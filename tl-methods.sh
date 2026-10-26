# tl-methods.sh — os DOIS métodos de TL (sourceável; só bash + bc). Fonte única do calibreitor.sh, do
# build-and-test.sh e do test-calib-methods.sh. Formato do pacote: cdmoj/docs/PACOTE.md.
#
#   MOJ    (o de sempre): TL[lang] = calibrafactor × W[lang] + 0,02  — fica no calibreitor.sh, intocado.
#   Kattis (spec 2025-09, "Problem timing"), POR LINGUAGEM (decisão do Ribas, 26/10/2026):
#          TLKATTIS[lang] = o menor múltiplo de r que é ≥ a × W[lang] (no mínimo r).
#   W[lang] = o pior tempo de teste AC das sols/good daquela linguagem — o MESMO dado dos dois métodos.
#
#   tl_method_of            -> moj|kattis: MOJ_TL_METHOD (o job, que o servidor tira do conf ATUAL) ›
#                              TLMETHOD (o conf do cache/local) › moj. Valor desconhecido = moj.
#   kattis_params           -> "a b r": KATTIS_AC_TO_TIME_LIMIT (2.0, 1..100), KATTIS_TIME_LIMIT_TO_TLE
#                              (1.5, 1..100), KATTIS_TIME_RESOLUTION (1.0, 0 < r ≤ 10), do conf já sourced.
#                              Inválido cai no padrão com AVISO no stderr (o validate-problem.sh reprova).
#   tl_kattis <W> <a> <r>   -> ⌈a·W/r⌉·r em bc (aritmética decimal: 2×0,45/0,1 dá 9, não 9,000…02),
#                              número limpo: "1", "0.9", "2.5".
#   tl_num <v>              -> verdadeiro se v é número decimal sem sinal ("1", ".5", "0.25").

tl_num(){ [[ "${1:-}" =~ ^([0-9]+\.?[0-9]*|\.[0-9]+)$ ]]; }

# número de bc -> forma limpa: ".9" -> "0.9", "3.0" -> "3", "2.50" -> "2.5"
_tlm_clean(){ sed -E 's/^\./0./; s/(\.[0-9]*[1-9])0+$/\1/; s/\.0*$//'; }

tl_method_of(){
  local m="${MOJ_TL_METHOD:-${TLMETHOD:-moj}}"
  [[ "$m" == kattis ]] && echo kattis || echo moj
}

# _tlm_in <v> <min> <max> <min-exclusivo?> — v é número dentro da faixa
_tlm_in(){
  tl_num "$1" || return 1
  local op='>='; [[ "${4:-}" == x ]] && op='>'
  [[ "$(echo "$1 $op $2 && $1 <= $3" | LC_ALL=C bc -l 2>/dev/null)" == 1 ]]
}

kattis_params(){
  local a="${KATTIS_AC_TO_TIME_LIMIT:-2.0}" b="${KATTIS_TIME_LIMIT_TO_TLE:-1.5}" r="${KATTIS_TIME_RESOLUTION:-1.0}"
  _tlm_in "$a" 1 100 || { echo "AVISO: KATTIS_AC_TO_TIME_LIMIT=$a inválido (número de 1 a 100): usando 2.0" >&2; a=2.0; }
  _tlm_in "$b" 1 100 || { echo "AVISO: KATTIS_TIME_LIMIT_TO_TLE=$b inválido (número de 1 a 100): usando 1.5" >&2; b=1.5; }
  _tlm_in "$r" 0 10 x || { echo "AVISO: KATTIS_TIME_RESOLUTION=$r inválido (número > 0 e ≤ 10): usando 1.0" >&2; r=1.0; }
  echo "$a $b $r"
}

tl_kattis(){
  local w="$1" a="$2" r="$3"
  LC_ALL=C bc -l <<<"x = $a * $w / $r; scale = 0; n = x / 1; if (n < x) n = n + 1; if (n < 1) n = 1; scale = 20; n * $r" \
    | _tlm_clean
}
