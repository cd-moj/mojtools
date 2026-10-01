#!/bin/bash
# install-fn.sh <pkgdir> [--langs "c cpp py java rs"] — instala os DRIVERS de submissão de
# função no pacote (scripts/<lang>/compile.sh, cópia real +x — o compile roda NA JAULA, onde
# o mojtools não existe). Fonte única: script-templates/submissao-de-funcao/files/ (o mesmo
# template do editor web). Depois de instalar, EDITE as zonas EDIT-ME de cada driver
# (protótipo, leitura, chamada) e lembre da SENTINELA: a última linha de todo tests/input/*
# é 424242. Guia completo: docs/submissao-de-funcao.md
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
TPL="$HERE/../script-templates/submissao-de-funcao/files"

pkg="${1:?uso: install-fn.sh <pkgdir> [--langs \"c cpp py java rs\"] [--force]}"; shift || true
[[ -d "$pkg" ]] || { echo "install-fn: pacote inexistente: $pkg" >&2; exit 1; }
langs="c cpp py java rs"; force=0
while [[ $# -gt 0 ]]; do case "$1" in
  --langs) langs="${2//,/ }"; shift 2;;
  --force) force=1; shift;;
  *) echo "install-fn: opção desconhecida: $1" >&2; exit 1;;
esac; done

# COMPOSIÇÃO por slots (ver docs/correcao-especial.md): este installer só preenche o slot
# COMPILE (scripts/<lang>/compile.sh) — compare.sh (checker) e summary.sh FICAM. O que NÃO
# compõe é o INTERATIVO: ele controla a execução por linguagem (scripts/<lang> vira symlink).
n=0
for l in $langs; do
  [[ -f "$TPL/$l/compile.sh" ]] || { echo "  ⚠ sem template p/ linguagem '$l' (tem: c cpp py java rs) — pulada" >&2; continue; }
  if [[ -L "$pkg/scripts/$l" ]]; then
    echo "  ⚠ scripts/$l é SYMLINK (pacote interativo?) — interativo × submissão-de-função NÃO compõem; '$l' pulada" >&2
    continue
  fi
  if [[ -f "$pkg/scripts/$l/run.sh" && $force -eq 0 ]]; then
    echo "  ⚠ scripts/$l/run.sh existe (interativo?) — '$l' pulada (use --force p/ sobrescrever o compile mesmo assim)" >&2
    continue
  fi
  if [[ -f "$pkg/scripts/$l/compile.sh" && $force -eq 0 ]]; then
    echo "  ⚠ scripts/$l/compile.sh JÁ existe — preservado (use --force p/ trocar pelo template)" >&2
    continue
  fi
  mkdir -p "$pkg/scripts/$l"
  cp "$TPL/$l/compile.sh" "$pkg/scripts/$l/compile.sh"
  chmod +x "$pkg/scripts/$l/compile.sh"
  echo "  scripts/$l/compile.sh instalado"
  n=$((n+1))
done
(( n > 0 )) || { echo "install-fn: nenhuma linguagem instalada" >&2; exit 1; }

# FUNCTION_LANGS no conf (cdmoj/docs/PACOTE.md): é ELA que diz ao editor (treino e o módulo `esqueletos`
# do contest) que nessas linguagens o aluno escreve SÓ a função — sem ela o editor mostraria o
# esqueleto com main (CE por main duplicado). União com o que já estava declarado; ids canônicos.
# A linha entra no COMEÇO do conf (o tl-checksum a ignora; no começo, o conf filtrado fica byte a byte o
# de antes) ou troca no lugar (o awk normaliza o \n final — sem efeito prático: instalar driver já
# mexeu em scripts/, e o problema recalibra de todo jeito). Sem `sed -i`: o `moj fn` roda isto na
# máquina do autor, que pode ser um Mac (o -i do BSD é outro).
source "$HERE/../lang-canon.sh"
_cur="$(sed -nE 's/^[[:space:]]*FUNCTION_LANGS=["'"'"']?([^"'"'"'#]*).*/\1/p' "$pkg/conf" 2>/dev/null | tail -1 || true)"
_all=""; IFS=', ' read -ra _decl <<<"$_cur"; _dirs=()
while IFS= read -r _d; do _dirs+=("$_d"); done < <(find "$pkg/scripts" -mindepth 2 -maxdepth 2 -name compile.sh 2>/dev/null | sed 's@/compile.sh$@@; s@.*/@@' | sort)
for _l in "${_decl[@]}" "${_dirs[@]}"; do
  _c="$(lang_canon "$_l")"
  [[ "$_c" =~ ^[a-z0-9]{1,16}$ && ",$_all," != *",$_c,"* ]] || continue
  # só entra linguagem declarada antes OU instalada agora (o compile.sh de ban/OpenMP não é de função)
  [[ " ${_decl[*]} " == *" $_l "* || " $langs " == *" $_l "* ]] && _all+="${_all:+,}$_c"
done
if [[ -n "$_all" ]]; then
  _tmp="$pkg/.conf.install-fn.$$"
  if grep -qE '^[[:space:]]*FUNCTION_LANGS[[:space:]]*=' "$pkg/conf" 2>/dev/null; then
    awk -v v="FUNCTION_LANGS=$_all" '/^[[:space:]]*FUNCTION_LANGS[[:space:]]*=/ && !d { print v; d = 1; next } { print }' "$pkg/conf" > "$_tmp"
  else
    { printf 'FUNCTION_LANGS=%s\n' "$_all"; if [[ -f "$pkg/conf" ]]; then cat "$pkg/conf"; fi; } > "$_tmp"
  fi
  mv -f "$_tmp" "$pkg/conf" && echo "conf: FUNCTION_LANGS=$_all (o editor abre vazio nessas linguagens)"
fi
_pres=""
[[ -f "$pkg/scripts/compare.sh" ]] && _pres+=" compare.sh(checker)"
[[ -f "$pkg/scripts/summary.sh" ]] && _pres+=" summary.sh"
[[ -n "$_pres" ]] && echo "slots PRESERVADOS (compõem com a submissão de função):$_pres"

cat <<'DICAS'
próximos passos:
  1. edite as zonas EDIT-ME de cada scripts/<lang>/compile.sh (protótipo, leitura, chamada)
     — MESMO nome de função em todas as linguagens liberadas;
  2. termine TODO tests/input/* com a linha da SENTINELA: 424242
     (é ela que pega função que consome a entrada — vira SENTINELA-VIOLADA => WA);
  3. sols/good/ recebe SÓ a função (sem main); uma good POR linguagem liberada;
  4. restrinja `languages` do problema às linguagens COM driver (senão trocar de
     linguagem burla o esquema);
  5. mexer em scripts/ muda o tl-checksum => o Painel vai pedir recalibração (correto);
  6. exemplo: se mostrar a entrada do driver não faz sentido p/ o aluno, declare SAMPLE=no no
     conf e explique a chamada no texto do enunciado (seção ## Exemplo). Com exemplo, use um
     tests/input/sample1 + uma nota docs/notes/sample1.md dizendo o que o driver faz com ele;
  7. FUNCTION_LANGS no conf já lista as linguagens com driver: se apagar o compile.sh de uma
     delas, tire-a da linha também (a validação reprova linguagem listada sem driver).
guia completo: mojtools/docs/submissao-de-funcao.md
DICAS
