#!/bin/bash
# stress-cage.sh — bateria de ESTRESSE do sandbox (rodar NUM JUIZ real antes de prova
# adversária): fork-bomb, alocação desenfreada, escrita em massa, rede, e leitura fora
# da jaula. Cada caso roda via cage-run.sh com os MESMOS parâmetros do julgamento e o
# resultado esperado é a CONTENÇÃO (processo morto/limitado, host intacto).
#
#   uso: bash stress-cage.sh [MEMLIMIT_MB]      (default 600; usa CAGE_ROOT se setado)
#
# Saída: PASS/FAIL por caso. QUALQUER FAIL = não use a máquina em prova hostil.
set -u
SELF="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
MEM="${1:-600}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/dir" "$W/rw"
: > "$W/in"

pass=0; fail=0
run(){ # run <nome> <script-body> <check: recebe stdout-file stderr-file rc>
  local name="$1" body="$2" check="$3" rc
  printf '#!/bin/bash\n%s\n' "$body" > "$W/script.sh"
  chmod +x "$W/script.sh"   # o cage exige -r executável (sem isso TODO caso falhava rc=2 e
                            # checks lenientes davam falso PASS com saída vazia)
  : > "$W/out"; : > "$W/err"; : > "$W/tl"; : > "$W/bt"
  bash "$SELF/cage-run.sh" ${CAGE_ROOT:+-R "$CAGE_ROOT"} \
    -d "$W/dir" -i "$W/in" -o "$W/out" -r "$W/script.sh" \
    -s "$W/err" -t "$W/tl" -T 10 -B "$W/bt" -M "$MEM" >/dev/null 2>&1
  rc=$?
  if eval "$check"; then echo "  PASS: $name"; ((pass++)); else echo "  FAIL: $name (rc=$rc)"; ((fail++)); fi
}

echo "== stress do cage (MEM=${MEM}MB, root=${CAGE_ROOT:-host}) =="

# 1. fork-bomb: deve morrer contido (ulimit -u/cgroup); o host segue vivo (nós estamos vivos)
run "fork-bomb contida" \
  ':(){ :|:& };: ; sleep 8' \
  'true'

# 2. alocação desenfreada: com cgroup (root ou systemd-run --user) o processo morre ANTES
#    de tocar swap; sem cgroup, o RSS medido detecta MLE depois. Aqui só exigimos contenção.
run "OOM contido" \
  'python3 -c "a=[];
import itertools
for i in itertools.count(): a.append(bytearray(64*1024*1024))" 2>/dev/null; true' \
  'true'

# 3. escrita em massa: ulimit -f (100MB) corta o arquivo
run "escrita em massa limitada" \
  'dd if=/dev/zero of=/tmp/flood bs=1M count=2048 2>/dev/null; stat -c %s /tmp/flood > /tmp/out 2>/dev/null || echo 0 > /tmp/out' \
  '[[ "$(cat "$W/out" 2>/dev/null | tr -d "[:space:]")" -le $((110*1024*1024)) ]]'

# 4. rede: --unshare-all derruba a rede — qualquer conexão TEM de falhar
run "sem rede" \
  'if timeout 3 bash -c "exec 3<>/dev/tcp/1.1.1.1/80" 2>/dev/null; then echo NET > /tmp/out; else echo OK > /tmp/out; fi' \
  '[[ "$(cat "$W/out" 2>/dev/null | tr -d "[:space:]")" == OK ]]'

# 5. leitura fora da jaula: $HOME do operador não pode estar visível
run "home invisível" \
  "if ls '$HOME' >/dev/null 2>&1; then echo LEAK > /tmp/out; else echo OK > /tmp/out; fi" \
  '[[ "$(cat "$W/out" 2>/dev/null | tr -d "[:space:]")" == OK ]]'

# 6. segredos de /etc mascarados: shadow vazio/ilegível, passwd só com a linha do 65534,
#    sudoers.d e /etc/ssh vazios (o /etc entra INTEIRO na jaula, com máscaras por cima)
run "segredos de /etc invisíveis" \
  'bad=""
   [[ -s /etc/shadow ]] && bad+="shadow "
   n=$(grep -c . /etc/passwd 2>/dev/null); [[ "${n:-0}" -gt 1 ]] && bad+="passwd($n) "
   [[ -n "$(ls -A /etc/sudoers.d 2>/dev/null)" ]] && bad+="sudoers.d "
   [[ -n "$(ls -A /etc/ssh 2>/dev/null)" ]] && bad+="ssh "
   [[ -s /etc/sudoers ]] && bad+="sudoers "
   if [[ -n "$bad" ]]; then echo "LEAK $bad" > /tmp/out; else echo OK > /tmp/out; fi' \
  '[[ "$(cat "$W/out" 2>/dev/null | tr -d "[:space:]")" == OK ]]'

echo
echo "RESULT: $pass passed, $fail failed"
echo "(nota: no caso 2, confirme no juiz que o processo morreu por cgroup — journalctl --user"
echo " mostra o oom-kill do scope — e não derrubou a máquina em swap.)"
exit $(( fail>0?1:0 ))
