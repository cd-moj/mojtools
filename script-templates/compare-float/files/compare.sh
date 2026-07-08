#!/bin/bash
# Comparador de PONTO FLUTUANTE por token: aceita se cada token numérico difere do esperado
# por <= EPS (absoluto) OU <= EPS_REL (relativo, se > 0). Tokens não-numéricos comparam exato.
# Contrato MOJ: $1=saída do time, $2=saída esperada, $3=entrada; exit 4=AC, 6=WA.
EPS=1e-3
EPS_REL=0        # ex.: 1e-9 p/ magnitudes grandes (Java %f zera dígitos de doubles enormes)

TEAM="${1:?}"; ANS="${2:?}"
[[ -r "$TEAM" && -r "$ANS" ]] || { echo "Parameter problem"; exit 43; }

if awk -v eps="$EPS" -v epsr="$EPS_REL" '
  function isnum(x){ return (x ~ /^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/) }
  function abs(x){ return x<0 ? -x : x }
  {
    n = split($0, a)
    if ((getline line2 < ansfile) <= 0) exit 1   # time tem linha a MAIS que o esperado
    m = split(line2, b)
    if (n != m) { exit 1 }
    for (i = 1; i <= n; i++) {
      if (isnum(a[i]) && isnum(b[i])) {
        d = abs(a[i]-b[i]); r = abs(b[i])>0 ? d/abs(b[i]) : d
        if (d > eps && (epsr == 0 || r > epsr)) exit 1
      } else if (a[i] != b[i]) exit 1
    }
  }
  END { if ((getline extra < ansfile) > 0 && extra ~ /[^[:space:]]/) exit 1 }
' ansfile="$ANS" "$TEAM"; then
  echo "AC (tolerância eps=$EPS rel=$EPS_REL)"
  exit 4
fi
echo "Differences found (fora da tolerância eps=$EPS rel=$EPS_REL)"
exit 6
