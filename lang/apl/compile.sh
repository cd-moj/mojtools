#!/bin/bash

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

# O `dyalog -script` NÃO executa a última linha sem `\n` no fim — e o editor web manda o texto sem ele: a
# resposta saía no `⎕NPUT` da última linha e a saída ficava vazia (submissão 1096ee5b, 31/10/2026: 0/25; com o
# `\n` acrescentado, 23/25). Garante o `\n` final no arquivo que o run.sh vai executar (vale p/ o editor E p/ o
# arquivo enviado). Nome do arquivo sempre citado: ele chega como o aluno mandou.
for f in *apl*; do
  [[ -f "$f" && -n "$(tail -c1 -- "$f")" ]] && printf '\n' >> "$f"
done

echo BIN=$(ls *apl*)
