#!/bin/bash
# interactive/test-driver.sh — MATRIZ DE REGRESSÃO do driver interativo (run.sh).
#
# Cobre o contrato pós-morte (bug do SIGPIPE, 2026-08-06): jogador que morre/sai sem ler a
# resposta pendente vira RTE/WA (nunca UE); árbitro py com BrokenPipeError não vira AC falso;
# árbitro genuinamente bugado segue UE; TERM (TL) inalterado.
#
# Roda FORA da jaula (dev ou container) e usa os caminhos /tmp FIXOS do driver — NÃO rode
# numa máquina com julgamento ativo. Precisa: bash, python3, /bin/time (GNU), mkfifo.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"
TMPFILES=(/tmp/dir /tmp/fifo.in /tmp/fifo.out /tmp/out /tmp/in
          /tmp/arbitro.log /tmp/arbitro.time /tmp/aluno.log /tmp/aluno.time /tmp/stderrlog)
trap 'rm -rf "$W" "${TMPFILES[@]}"' EXIT

# ---------- árbitros de teste (protocolo: PING -> PONG, 2x; resultado "10" no stderr) ------
cat > "$W/arb.sh" <<'EOF'
#!/bin/bash
echo "PING"
read -r r; [[ "$r" == PONG ]] || { echo "WRONG resposta errada" >&2; exit 0; }
echo "log benigno (nao pode virar resultado)" >&2
sleep 0.4   # determinismo do teste: garante que o jogador sumido já fechou o FIFO
echo "PING"
read -r r; [[ "$r" == PONG ]] || { echo "WRONG resposta errada" >&2; exit 0; }
echo "10" >&2
exit 0
EOF
cat > "$W/arb-patched.sh" <<'EOF'
#!/bin/bash
trap 'printf "WRONG o programa encerrou sem ler a resposta\n" >&2; exit 0' PIPE
echo "PING"
read -r r; [[ "$r" == PONG ]] || { echo "WRONG resposta errada" >&2; exit 0; }
echo "log benigno (nao pode virar resultado)" >&2
sleep 0.4   # determinismo do teste: garante que o jogador sumido já fechou o FIFO
echo "PING"
read -r r; [[ "$r" == PONG ]] || { echo "WRONG resposta errada" >&2; exit 0; }
echo "10" >&2
exit 0
EOF
cat > "$W/arb.py" <<'EOF'
#!/usr/bin/env python3
import sys, time
def ask():
    print("PING", flush=True)
    return sys.stdin.readline().strip()
if ask() != "PONG":
    print("WRONG resposta errada", file=sys.stderr); sys.exit(0)
print("log benigno (nao pode virar resultado)", file=sys.stderr)
time.sleep(0.4)   # determinismo: o jogador sumido já fechou o FIFO
if ask() != "PONG":
    print("WRONG resposta errada", file=sys.stderr); sys.exit(0)
print("10", file=sys.stderr)
EOF
cat > "$W/arb-patched.py" <<'EOF'
#!/usr/bin/env python3
import os, sys, time
def main():
    def ask():
        print("PING", flush=True)
        return sys.stdin.readline().strip()
    if ask() != "PONG":
        print("WRONG resposta errada", file=sys.stderr); return
    print("log benigno (nao pode virar resultado)", file=sys.stderr)
    time.sleep(0.4)   # determinismo: o jogador sumido já fechou o FIFO
    if ask() != "PONG":
        print("WRONG resposta errada", file=sys.stderr); return
    print("10", file=sys.stderr)
try:
    main()
except BrokenPipeError:
    print("WRONG o programa encerrou sem ler a resposta", file=sys.stderr)
    sys.stderr.flush()
    os._exit(0)   # o flush do stdout QUEBRADO na saída do interpretador viraria exit != 0
sys.exit(0)
EOF
cat > "$W/arb-segv.py" <<'EOF'
#!/usr/bin/env python3
import os, signal, sys
print("PING", flush=True)
sys.stdin.readline()
os.kill(os.getpid(), signal.SIGSEGV)   # árbitro genuinamente bugado
EOF
cat > "$W/arb-wrong-exit1.sh" <<'EOF'
#!/bin/bash
echo "PING"
read -r r
[[ "$r" == PONG ]] || { echo "WRONG resposta errada" >&2; exit 1; }  # árbitro ANTIGO: WRONG + exit != 0
echo "10" >&2; exit 0
EOF

# ---------- jogadores de teste --------------------------------------------------------------
cat > "$W/pl-ok.sh"    <<'EOF'
#!/bin/bash
read -r l; echo "PONG"; read -r l; echo "PONG"; exit 0
EOF
cat > "$W/pl-exit0.sh" <<'EOF'
#!/bin/bash
read -r l; echo "PONG"; exit 0        # sai SEM ler a resposta pendente (protocolo incompleto)
EOF
cat > "$W/pl-die.sh"   <<'EOF'
#!/bin/bash
read -r l; echo "PONG"; exit 7        # "crash" (exit != 0) sem ler a resposta pendente
EOF
cat > "$W/pl-segv.py"  <<'EOF'
#!/usr/bin/env python3
import os, signal, sys
sys.stdin.readline(); print("PONG", flush=True)
os.kill(os.getpid(), signal.SIGSEGV)
EOF
cat > "$W/pl-wrong.sh" <<'EOF'
#!/bin/bash
read -r l; echo "NOPE"; read -r l; exit 0
EOF
cat > "$W/pl-sleep.sh" <<'EOF'
#!/bin/bash
sleep 300
EOF
chmod +x "$W"/*.sh "$W"/*.py

pass=0; fail=0
ck(){ if eval "$2"; then echo "  ok: $1"; ((pass++)); else
        echo "  FAIL: $1 :: rc=$RC out=[$(cat /tmp/out 2>/dev/null | head -1)]"; ((fail++))
        sed -n '1,25p' /tmp/stderrlog 2>/dev/null | sed 's/^/    | /'
      fi; }

# run_case <árbitro> <jogador> [term]  -> RC + /tmp/out
run_case(){
  rm -rf "${TMPFILES[@]}"
  mkdir -p /tmp/dir
  cp "$W/$1" /tmp/dir/arbitro
  cp "$W/$2" "/tmp/dir/$2"
  printf 'BIN=%s\n' "$2" > /tmp/dir/binfile.sh
  printf 'teste\n' > /tmp/in
  : > /tmp/out
  if [[ "${3:-}" == term ]]; then
    bash "$HERE/run.sh" & local pid=$!
    sleep 1.5; kill -TERM "$pid" 2>/dev/null
    wait "$pid"; RC=$?
    pkill -f 'sleep 300' 2>/dev/null; sleep 0.2
  else
    bash "$HERE/run.sh"; RC=$?
  fi
}
out_is(){ [[ "$(cat /tmp/out 2>/dev/null)" == $1 ]]; }

echo "== caminho feliz =="
run_case arb.sh pl-ok.sh;              ck "AC (árbitro sh): rc0 + score"      '[[ $RC == 0 ]] && out_is "10"'
run_case arb.py pl-ok.sh;              ck "AC (árbitro py): rc0 + score"      '[[ $RC == 0 ]] && out_is "10"'
run_case arb.sh pl-wrong.sh;           ck "WA clássico (WRONG do árbitro)"    '[[ $RC == 0 ]] && out_is "WRONG resposta errada"'

echo "== o BUG: jogador some sem ler (árbitro morre de SIGPIPE) =="
run_case arb.sh pl-exit0.sh;           ck "saiu 0 sem ler -> WRONG sintético" '[[ $RC == 0 ]] && out_is "WRONG o programa encerrou sem ler*"'
run_case arb.sh pl-die.sh;             ck "morreu (exit!=0) sem ler -> RTE"   '[[ $RC == 3 ]]'
run_case arb.sh pl-segv.py;            ck "morreu (SIGSEGV) sem ler -> RTE"   '[[ $RC == 3 ]]'

echo "== agravante: árbitro PY com BrokenPipeError (era AC FALSO) =="
run_case arb.py pl-die.sh;             ck "py sem patch + jogador morto -> RTE (nunca AC)" '[[ $RC == 3 ]]'
run_case arb.py pl-exit0.sh;           ck "py sem patch + saiu 0 -> UE (out vazio; nunca AC)" '[[ $RC == 0 ]] && [[ ! -s /tmp/out ]]'

echo "== árbitros com a proteção (camada 1): WRONG com motivo =="
run_case arb-patched.sh pl-exit0.sh;   ck "sh patched: WRONG do árbitro"      '[[ $RC == 0 ]] && out_is "WRONG o programa encerrou sem ler*"'
run_case arb-patched.py pl-die.sh;     ck "py patched: resultado MANDA (WA)"  '[[ $RC == 0 ]] && out_is "WRONG o programa encerrou sem ler*"'

echo "== árbitro genuinamente bugado / compat =="
run_case arb-segv.py pl-ok.sh;         ck "árbitro SIGSEGV -> UE (out vazio)" '[[ $RC == 0 ]] && [[ ! -s /tmp/out ]]'
run_case arb-wrong-exit1.sh pl-wrong.sh; ck "árbitro antigo WRONG+exit1 -> WA" '[[ $RC == 0 ]] && out_is "WRONG resposta errada"'

echo "== TERM (TL): caminho inalterado =="
run_case arb.sh pl-sleep.sh term;      ck "TERM -> exit 0 (TLE sai pelo tempo)" '[[ $RC == 0 ]]'

echo; echo "passed=$pass failed=$fail"
(( fail == 0 ))
