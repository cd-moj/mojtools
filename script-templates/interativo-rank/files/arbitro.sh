#!/bin/bash
# EXEMPLO de árbitro: "adivinha o número" — adapte (tutorial: mojtools/docs/problema-interativo.md)
# Contrato: teste em $1; stdout->jogador; stdin<-jogador; ÚLTIMA linha do stderr = resultado
# (score no sucesso, "WRONG <motivo>" no erro); exit SEMPRE 0.
read -r ALVO MAX < "$1"
echo "$MAX"
for ((i=1; i<=MAX; i++)); do
  read -r palpite || { echo "WRONG jogador encerrou sem acertar" >&2; exit 0; }
  echo "palpite $i: $palpite" >&2
  if (( palpite == ALVO )); then
    echo OK
    echo "$((MAX - i + 1))" >&2
    exit 0
  fi
  (( palpite < ALVO )) && echo MAIOR || echo MENOR
done
echo "WRONG estourou as $MAX tentativas" >&2
