#!/bin/bash
# scripts/c/run.sh — MPI: um processo por CPU do problema. MOJ_TEST_CPUS vem do binfile.sh
# (= CPUNEEDED do conf, ou o que o agente deu ao teste) — NUNCA um -np fixo: o tempo-limite foi
# medido com exatamente essas CPUs. Roda DENTRO da jaula. Guia: mojtools/docs/problema-paralelo.md
#   --bind-to none: a afinidade já é a do grupo de CPUs do teste (taskset do juiz); deixar a
#     OpenMPI re-pinar por baixo só atrapalha.  --oversubscribe: dentro da jaula ela pode ver
#     menos "slots" do que CPUs.  pipefail: o exit do aluno é o que conta (o `| grep -v UCX` de
#     pacotes antigos mascarava o código de saída: RE virava AC/WA).

exec &>/tmp/stderrlog

cd /tmp/dir
source binfile.sh
set -o pipefail

exec mpirun --bind-to none --oversubscribe -np "${MOJ_TEST_CPUS:-1}" ./"$BIN" < /tmp/in > /tmp/out
