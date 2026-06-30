# score-summary.sh — pontuação por GRUPOS (subtasks) genérica do CD-MOJ.
#
# Sourced por build-and-test.sh (veja "FINAL VERDICT") quando o pacote tem um
# arquivo tests/score mas NÃO traz um scripts/summary.sh próprio. Generaliza o
# summary.sh histórico dos problemas da OBI
# (moj-problems/obi-problems/*/scripts/summary.sh) num único script reutilizável.
#
# Formato de tests/score — uma linha por grupo:
#     <glob> - <peso> pontos          ex.:  g2_* - 20 pontos
# Cada teste é associado ao seu grupo pelo NOME do arquivo de entrada, tirando os
# dígitos finais (ex.: g2_03 -> grupo "g2_", casado pelo glob "g2_*"). Por isso o
# prefixo do grupo deve terminar em não-dígito (use "<grupo>_<NN>").
#
# Pontuação TUDO-OU-NADA por grupo: o grupo só vale seus pontos se TODOS os seus
# testes derem AC. FINALRESP é sobrescrito com os pontos somados dos grupos 100%
# aceitos (Accepted,100p quando completo; senão Wrong,<ganhos>p + detalhamento).
#
# Variáveis de ambiente esperadas (já definidas por build-and-test.sh):
#   PROBLEMTEMPLATEDIR  - diretório do pacote do problema (tem tests/score)
#   workdirbase         - diretório de trabalho (tem log.verdictall: VERDICT[in]=..)
#   LOG()               - função de log (stderr)

declare -A GROUPFFS      # nome-do-grupo  -> índice do grupo em GROUP[]
declare -a GROUP         # índice         -> peso (pontos)
declare -A SOMA          # "idx,AC"/"idx,WRONG" -> contagem
TOTAL=0

if [[ -e "$PROBLEMTEMPLATEDIR/tests/score" ]]; then
  while IFS='-' read -r GRUPO SCORE; do
    [[ -z "${GRUPO//[[:space:]]/}" ]] && continue          # linha em branco
    for PAT in $GRUPO; do
      groupname="${PAT%\**}"; groupname="${groupname%,}"    # tira o "*" final (e vírgula)
      GROUPFFS[$groupname]=${#GROUP[@]}
      SOMA[${#GROUP[@]},AC]=0
      SOMA[${#GROUP[@]},WRONG]=0
    done
    gval="${SCORE//[^0-9]/}"; gval=${gval:-0}               # extrai o número de "... pontos"
    GROUP+=( "$gval" )
    (( TOTAL += gval ))
  done < "$PROBLEMTEMPLATEDIR/tests/score"
else
  LOG "# score-summary: pacote sem tests/score — considerando grupo único"
fi

# O VALOR do problema é a soma dos pesos dos grupos (definida pelo autor; pode passar de 100).
# Não há grupo extra automático: todo teste precisa casar com um grupo (os exemplos entram como
# "sample* - 0 pontos"); um teste sem grupo é erro de configuração e zera a submissão.
EXTRAGROUP=""

declare -A VERDICT
source "$workdirbase/log.verdictall"

declare -A RESPOSTASCOUNT
shopt -s extglob &>/dev/null
NOGROUP=""
for INPUT in "${!VERDICT[@]}"; do
  groupname="${INPUT%%+([0-9])}"                            # tira os dígitos finais
  [[ -n "${GROUPFFS[$INPUT]}" ]] && groupname="$INPUT"      # nome exato também vale como grupo
  [[ -z "${GROUPFFS[$groupname]}" && -n "$EXTRAGROUP" ]] && GROUPFFS[$groupname]=$EXTRAGROUP
  if [[ -z "${GROUPFFS[$groupname]}" ]]; then
    LOG "- score-summary: sem grupo para o teste '$INPUT'"; NOGROUP="$INPUT"; break
  fi
  gi=${GROUPFFS[$groupname]}
  if [[ ${VERDICT[$INPUT]} =~ AC ]]; then (( SOMA[$gi,AC]++ )); else (( SOMA[$gi,WRONG]++ )); fi
  (( RESPOSTASCOUNT[${VERDICT[$INPUT]}]++ ))
done

# soma os pontos: grupo vale o peso só se 0 WRONG e >=1 AC.
EARNED=0; FAILED=0; BREAK="Pontos |"
for (( g=0; g<${#GROUP[@]}; g++ )); do
  if (( ${SOMA[$g,WRONG]:-0} == 0 && ${SOMA[$g,AC]:-0} > 0 )); then
    (( EARNED += ${GROUP[$g]} ))
    (( ${GROUP[$g]} == 0 )) && continue                    # grupo de 0 ponto (público) não entra no detalhe
    BREAK+=" ${GROUP[$g]} |"
  elif (( ${SOMA[$g,WRONG]:-0} > 0 )); then
    (( FAILED++ )); BREAK+=" 0 |"
  else
    (( FAILED++ )); BREAK+=" -1 |"                          # grupo sem nenhum teste executado
  fi
done

QUANT=""
if (( FAILED > 0 )); then
  QUANT=" quantitativos"
  for k in "${!RESPOSTASCOUNT[@]}"; do QUANT+=" $k(${RESPOSTASCOUNT[$k]})"; done
fi

# Accepted só quando NENHUM grupo falhou (todos com >=1 teste e todos AC); o valor é a soma
# total dos pesos. Senão, soma dos pesos dos grupos 100% aceitos (pontuação parcial).
# score estruturado por pontos (subtask): o backend casa pelo VERDICT_CANON e o treino mostra E/T pontos
SCORE_KIND=points; SCORE_MAX=$TOTAL
if [[ -n "$NOGROUP" ]]; then
  FINALRESP="Wrong,0p. teste '$NOGROUP' sem grupo em tests/score"
  VERDICT_CANON="Wrong Answer"; SCORE=0
elif (( FAILED == 0 )); then
  FINALRESP="Accepted,${TOTAL}p. $BREAK"
  VERDICT_CANON="Accepted"; SCORE=$TOTAL
else
  FINALRESP="Wrong,${EARNED}p. $BREAK$QUANT"
  VERDICT_CANON="Wrong Answer"; SCORE=$EARNED
fi
LOG ""
LOG "- score-summary FINALRESP: $FINALRESP"
LOG ""
