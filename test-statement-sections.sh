#!/bin/bash
# test-statement-sections.sh — as SEÇÕES obrigatórias do enunciado (validate-problem.sh, 05/11/2026; relato do Daniel
# Saad e do Roberto Sales). `## Entrada` + `## Saída` seguem obrigatórias, mas uma seção `## Interação` (Interaction,
# Interacción — a convenção do Kattis) vale pelo PAR: o interativo não precisa mais do "## Input / See the Interaction
# section" só p/ passar. Garante, rodando o validate-problem.sh REAL num pacote temporário:
#   · Entrada+Saída passam (como sempre); só Interação passa, com o detalhe "dispensada";
#   · sem nenhuma das duas formas reprova (a mensagem cita a Interação);
#   · tradução: "## Interaction" (en) e "## Interacción" (es) valem; "## Interacao" sem acento e INTERAÇÃO maiúsculo
#     também (o grep da imagem roda em locale POSIX, sem dobra de multibyte);
#   · NÃO é o SAMPLE=no que dispensa: função com SAMPLE=no e sem ## Entrada segue reprovando;
#   · avisos soft: interativo (scripts/arbitro.*) sem a seção; a seção substituindo Entrada/Saída sem árbitro.
set -u
MT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export CONTESTSDIR="$W/c" RUNDIR="$W/run" VALIDATE_RUN_SOLS=0 LC_ALL=C
mkdir -p "$CONTESTSDIR/treino/var/jsons" "$RUNDIR"
pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else echo "  FAIL: $1 :: $(jq -c "$3" "$R" 2>/dev/null | head -c 300)"; ((fail++)); fi; }
P="$W/repo/pp"
mkpkg(){  # mkpkg <enunciado PT> [conf]
  rm -rf "$P"; mkdir -p "$P/docs" "$P/tests/input" "$P/tests/output" "$P/sols/good" "$P/scripts"
  printf '%s\n' "$1" > "$P/docs/enunciado.md"; printf 'CALIBRATIONTL=5\n%s\n' "${2:-SAMPLE=no}" > "$P/conf"
  echo 1 > "$P/tests/input/t1"; echo 1 > "$P/tests/output/t1"; echo autor > "$P/author"; echo 'int main(){}' > "$P/sols/good/a.c"
}
R="$W/run/validation/x.json"
val(){ rm -f "$RUNDIR"/validation/*.json; bash "$MT/validate-problem.sh" "$P" x >/dev/null 2>&1; }
chk(){ jq -r --arg n "$1" '.checks[] | select(.name == $n) | "\(.ok)|\(.detail // "")"' "$R" 2>/dev/null; }
warn(){ jq -r '.render_warnings // ""' "$R" 2>/dev/null; }

echo "== PT =="
mkpkg $'Descrição.\n\n## Entrada\n\nUm inteiro.\n\n## Saída\n\nOutro.'; val
ck "Entrada + Saída: passam (como sempre)"           '[[ "$(chk secao_entrada)" == "true|" && "$(chk secao_saida)" == "true|" ]]' '.checks'
mkpkg $'Descrição.\n\n## Interação\n\nO juiz manda N; você pergunta.\n\n## Exemplo\n\n| juiz | você |'; val
ck "só Interação: as duas passam, 'dispensada'"      '[[ "$(chk secao_entrada)" == "true|dispensada"* && "$(chk secao_saida)" == "true|dispensada"* ]]' '.checks'
mkpkg $'Descrição.\n\n## Exemplo\n\nnada'; val
ck "nenhuma das duas: reprova, citando a Interação"  '[[ "$(chk secao_entrada)" == "false|"*Interação* && "$(chk secao_saida)" == "false|"*Interação* && "$(jq -r .ok "$R")" == false ]]' '.checks'
mkpkg $'Descrição.\n\n### Interacao\n\nsem acento'; val
ck "### Interacao (sem acento, 3 #) vale"            '[[ "$(chk secao_entrada)" == "true|dispensada"* ]]' '.checks'
mkpkg $'Descrição.\n\n## INTERAÇÃO\n\nmaiúsculo'; val
ck "## INTERAÇÃO maiúsculo vale no locale POSIX"     '[[ "$(chk secao_saida)" == "true|dispensada"* ]]' '.checks'
mkpkg $'Descrição.\n\n## Interação\n\nx\n\n## Saída\n\ny'; val
ck "Interação + só Saída: Saída conta como ela mesma" '[[ "$(chk secao_entrada)" == "true|dispensada"* && "$(chk secao_saida)" == "true|" ]]' '.checks'
mkpkg $'Descrição.\n\nUma interação comum no meio do texto.\n\n## Saída\n\ny'; val
ck "a palavra no TEXTO não é seção: reprova a entrada" '[[ "$(chk secao_entrada)" == "false|"* ]]' '.checks'

echo "== não é o SAMPLE=no que dispensa =="
mkpkg $'Implemente f(x).\n\n## Saída\n\nO retorno.' 'SAMPLE=no'; val
ck "função com SAMPLE=no e sem ## Entrada: reprova"  '[[ "$(chk secao_entrada)" == "false|"* ]]' '.checks'

echo "== traduções =="
mkpkg $'Descrição.\n\n## Interação\n\nx'
printf 'Description.\n\n## Interaction\n\nThe judge sends N.\n' > "$P/docs/enunciado.en.md"
printf 'Descripción.\n\n## Interacción\n\nEl juez envía N.\n' > "$P/docs/enunciado.es.md"
val
ck "en: ## Interaction vale"                         '[[ "$(chk secao_entrada_en)" == "true|dispensada"* && "$(chk secao_saida_en)" == "true|dispensada"* ]]' '.checks'
ck "es: ## Interacción vale"                         '[[ "$(chk secao_entrada_es)" == "true|dispensada"* && "$(chk secao_saida_es)" == "true|dispensada"* ]]' '.checks'
ck "…e o pacote inteiro passa"                       '[[ "$(jq -r "[.checks[]|select(.name|startswith(\"secao_\"))|.ok]|all" "$R")" == true ]]' '.checks'
printf 'Description.\n\n## Notes\n\nx\n' > "$P/docs/enunciado.en.md"; val
ck "en sem nenhuma: reprova, citando Interaction"    '[[ "$(chk secao_entrada_en)" == "false|"*Interaction* ]]' '.checks'

echo "== avisos soft de coerência =="
mkpkg $'Descrição.\n\n## Entrada\n\nN.\n\n## Saída\n\nPalpites.'; echo 'echo x' > "$P/scripts/arbitro.sh"; val
ck "interativo (arbitro) sem a seção: aviso, sem reprovar" '[[ "$(warn)" == *interativo-sem-secao-interacao* && "$(chk secao_entrada)" == "true|" ]]' '.render_warnings'
mkpkg $'Descrição.\n\n## Interação\n\nx'; echo 'echo x' > "$P/scripts/arbitro.sh"; val
ck "interativo com a seção: sem aviso"               '[[ "$(warn)" != *interacao* ]]' '.render_warnings'
mkpkg $'Descrição.\n\n## Interação\n\nx'; val
ck "a seção no lugar de Entrada/Saída SEM árbitro: aviso" '[[ "$(warn)" == *secao-interacao-sem-arbitro* ]]' '.render_warnings'
mkpkg $'Descrição.\n\n## Entrada\n\nN.\n\n## Saída\n\nM.\n\n## Interação\n\nx'; val
ck "Interação junto de Entrada e Saída, sem árbitro: sem aviso" '[[ "$(warn)" != *interacao* ]]' '.render_warnings'

echo; echo "RESULT: $pass passed, $fail failed"
(( fail == 0 ))
