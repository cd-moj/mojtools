#!/bin/bash
# scripts/c/run.sh (instalado por mojtools/interactive/install-interactive.sh; as demais
# linguagens symlinkam o diretório: scripts/<lang> -> c) — DRIVER COMUM de PROBLEMA
# INTERATIVO do MOJ. Roda ÁRBITRO + JOGADOR dentro da jaula, cruzando stdin/stdout por
# FIFOs, e materializa o RESULTADO em /tmp/out p/ o compare decidir o veredicto.
#
# Protocolo (tutorial: mojtools/docs/problema-interativo.md):
#   - árbitro = /tmp/dir/arbitro (materializado pelo prep.sh), recebe o teste em argv[1];
#   - árbitro stdout -> stdin do jogador; jogador stdout -> stdin do árbitro (stdbuf -oL);
#   - a ÚLTIMA linha do stderr do árbitro é o RESULTADO: score/info no sucesso,
#     "WRONG <motivo>" no erro. (Compat: árbitro que grava /tmp/out direto é respeitado.)
#   - O RESULTADO do árbitro MANDA: com resultado, o exit do jogador é ignorado;
#     sem resultado, jogador que morreu = RTE (exit 3) e silêncio = UE (compare 13).
#   - TL: o juiz manda TERM; materializamos o que houver e saímos 0 (o TLE sai pelo
#     tempo medido, como em qualquer problema).

exec 2>/tmp/stderrlog

# materializa /tmp/out: respeita se o árbitro já gravou algo; senão usa a última linha
# não-vazia do log (stderr) dele. NUNCA recriar /tmp/out (é um bind de arquivo): só '>'.
materializa() {
  [[ -s /tmp/out ]] && return 0
  [[ -s /tmp/arbitro.log ]] || return 0
  grep -v '^[[:space:]]*$' /tmp/arbitro.log | tail -n1 > /tmp/out
}

sai_tl() {
  echo "======== DRIVER: TERM recebido (time limit do jogador)" >&2
  cat /tmp/arbitro.log >&2 2>/dev/null
  materializa
  exit 0
}
trap sai_tl TERM

cd /tmp/dir
source binfile.sh

# dispatch de linguagem pela extensão do binário/fonte (testado: compilados ELF, py, sh,
# java, kt; melhor esforço: js — ver limitações no tutorial). Os ramos da JVM espelham
# lang/java/run.sh e lang/kt/run.sh (mesmas flags de heap/stack): java roda a CLASSE
# (compile.sh elege a que tem main), kotlin roda o JAR (kotlinc -include-runtime já põe o
# Main-Class no manifest). ⚠ na JVM o `stdbuf -oL` abaixo é NO-OP (I/O próprio, não libc):
# a solução TEM de dar flush a cada resposta — está no enunciado/tutorial.
CMD=(/tmp/dir/$BIN)
_JVM=(-Xms10m -Xmx${MOJ_MEMLIMITMB:-500}m -Xss${MOJ_STACKKB:-131072}k)
case "$BIN" in
  *.py|*.py2|*.py3) CMD=(python3 /tmp/dir/$BIN) ;;
  *.sh)             CMD=(bash /tmp/dir/$BIN) ;;
  *.js)             CMD=(node /tmp/dir/$BIN) ;;
  *.class)          export CLASSPATH=/tmp/dir
                    CMD=(java "${_JVM[@]}" "$(basename "$BIN" .class)") ;;
  *.jar)            CMD=(java "${_JVM[@]}" -jar /tmp/dir/$BIN) ;;
esac

mkfifo /tmp/fifo.in /tmp/fifo.out
cd /tmp/

stdbuf -oL /bin/time --output /tmp/aluno.time -f "%M %U" "${CMD[@]}" < /tmp/fifo.out > /tmp/fifo.in 2>/tmp/aluno.log &
stdbuf -oL /bin/time --output /tmp/arbitro.time -f "%M %U" /tmp/dir/arbitro /tmp/in > /tmp/fifo.out < /tmp/fifo.in 2> /tmp/arbitro.log &

wait

# log do árbitro + stderr do JOGADOR + medidas vão p/ o stderr (aparecem no report). O
# stderr do jogador é o único diagnóstico de exceção em JVM/Python — não jogar fora.
cat /tmp/arbitro.log >&2 2>/dev/null
if [[ -s /tmp/aluno.log ]]; then
  echo "======== stderr do jogador (últimas 40 linhas)" >&2
  tail -n 40 /tmp/aluno.log >&2 2>/dev/null
fi
read -r MEMORIA TEMPO <<< "$(tail -n1 /tmp/aluno.time 2>/dev/null)"
echo "Tempo do jogador (segundos de CPU): ${TEMPO:-?}" >&2
echo "Memória do jogador (KB): ${MEMORIA:-?}" >&2

# árbitro morto por sinal = erro do JUIZ: invalida qualquer resultado -> UE (compare 13)
if grep -qi "signal" /tmp/arbitro.time 2>/dev/null; then
  echo "DRIVER: árbitro terminou por SINAL — resultado invalidado (vira UE)" >&2
  : > /tmp/out
  exit 0
fi

materializa

# sem resultado do árbitro: jogador que morreu explica o silêncio -> RTE; senão UE
if [[ ! -s /tmp/out ]] && grep -Eqi "(non-zero|signal)" /tmp/aluno.time 2>/dev/null; then
  echo "DRIVER: jogador terminou com erro e o árbitro não produziu resultado -> Runtime Error" >&2
  exit 3
fi

exit 0
