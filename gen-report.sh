#!/bin/bash
#This file is part of CD-MOJ.
#
#CD-MOJ is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#CD-MOJ is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with CD-MOJ.  If not, see <http://www.gnu.org/licenses/>.

# gen-report.sh — gera report.org + report.html (auto-contido) a partir de um
# workdirbase de build-and-test.sh.
#   uso:  bash gen-report.sh <workdirbase>
# Lê <wb>/report.env (metadados) e <wb>/log.verdictall (mapa VERDICT[file]),
# mais os artefatos por teste em <wb>/<file>-*. Compila o .org com pandoc num
# único HTML embutido. Não escreve em stdout (o veredicto continua sendo do
# build-and-test.sh).

wb="${1:?uso: gen-report.sh <workdirbase>}"
[[ -d "$wb" ]] || { echo "gen-report: workdir '$wb' inexistente" >&2; exit 1; }

# defaults — tolera report.env incompleto (ex.: regeneração manual)
PROBLEM="" LANGUAGE="" SRCBASENAME="" TL_LANG="1" SMALLRESP="" FINALRESP=""
CORRECT=0 TOTALTESTS=0 TOTALTIME=0 PROBLEMTEMPLATEDIR="" HOSTBT="" STARTDATE=""
RUNALL="" NPROCINFO="" REPORTMODE="normal" TOOLCHAIN_ROOT="" TOOLCHAIN_VER=""
[[ -e "$wb/report.env" ]] && source "$wb/report.env"

declare -A VERDICT
[[ -e "$wb/log.verdictall" ]] && source "$wb/log.verdictall"

declare -A VERDICTFULLNAME=(
  [UE]="Unknown ERROR" [TLE]="Time Limit Exceeded" [MLE]="Memory Limit Exceeded" [RE]="Runtime Error"
  [RE_NZEC]="Possible Runtime Error, non-zero return"
  [TMT]="Runtime Error, signaled PPDI" [WA]="Wrong Answer"
  [AC]="Accepted" [AC,PE]="Accepted (Presentation Error)"
  [CE]="Compilation Error" [NT]="Não executado"
)

ORG="$wb/report.org"
HTML="$wb/report.html"
: > "$ORG"

# ---------------------------------------------------------------- helpers ----
o(){ printf '%s\n' "$*" >> "$ORG"; }
raw(){ printf '%s' "$*" >> "$ORG"; }

# escapa &<>" (stream) e neutraliza delimitador de bloco org (#+) no começo da
# linha, para conteúdo do usuário não fechar o #+BEGIN_EXPORT antes da hora.
esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' \
           -e 's/^\([[:space:]]*\)#+/\1#\&#43;/'; }
# idem, para uma string única (sem subprocesso). OBS: no bash 5.1+ um '&' na
# string de substituição de ${v//p/s} vira "o texto casado"; por isso usamos \&
# para inserir um '&' literal em &amp;/&lt;/&gt;/&quot;.
escs(){ local s="$1"; s=${s//&/\&amp;}; s=${s//</\&lt;}; s=${s//>/\&gt;}; s=${s//\"/\&quot;}
  [[ "$s" =~ ^([[:space:]]*)\#\+(.*)$ ]] && s="${BASH_REMATCH[1]}#&#43;${BASH_REMATCH[2]}"
  printf '%s' "$s"; }

slugify(){ printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
fullname(){ printf '%s' "${VERDICTFULLNAME[$1]:-$1}"; }

vcolor(){ case "$1" in
  AC|AC,PE) echo "#15803d";; WA) echo "#be1241";; TLE) echo "#9a6700";; MLE) echo "#b45309";;
  RE|RE_NZEC|TMT) echo "#d94f9a";; CE) echo "#7a5ada";; *) echo "#94a3b8";; esac; }
vkey(){ case "$1" in
  AC|AC,PE) echo ac;; WA) echo wa;; TLE|MLE) echo tle;;
  RE|RE_NZEC|TMT) echo re;; CE) echo ce;; *) echo gray;; esac; }

exectime_of(){ local f="$wb/$1-log.timelog"
  [[ -s "$f" ]] && grep -m1 '^real' "$f" 2>/dev/null | awk '{print $NF}'; }
# pico de RSS (memória residente real) em KB — res %M do /usr/bin/time. É o uso REAL de
# memória (não o virtual reservado), melhor p/ linguagens que reservam heaps grandes.
mem_of(){ local f="$wb/$1-log.timelog"
  [[ -s "$f" ]] && grep -m1 '^res' "$f" 2>/dev/null | awk '{print $NF}'; }
mem_fmt(){ awk -v k="${1:-0}" 'BEGIN{ if(k+0<=0){print "—"} else if(k+0<1024){printf "%d KB",k} else {printf "%.1f MB",k/1024} }'; }
# largura em % do tempo relativo ao TL (entre 2 e 100); vazio -> 0
pct_of(){ local t="$1" tl="${TL_LANG:-1}"; [[ -z "$t" ]] && { echo 0; return; }
  awk -v t="$t" -v tl="$tl" 'BEGIN{ if(tl+0<=0)tl=1; v=(t+0)/tl*100;
    if(v>100)v=100; if(v<2)v=2; printf "%.1f", v }' 2>/dev/null || echo 2; }

# <pre> com conteúdo de arquivo escapado e truncado. $1=arq $2=classe $3=maxlinhas
prefile(){ local f="$1" cls="${2:-}" max="${3:-200}" n
  [[ -s "$f" ]] || return 1
  n=$(wc -l < "$f")
  raw "<pre class=\"$cls\">"; head -n "$max" "$f" | esc >> "$ORG"; raw "</pre>"
  (( n > max )) && raw "<p class=\"muted\">… truncado: mostrando $max de $n linhas.</p>"
  raw $'\n'; return 0; }

# diff colorido (linhas </- = esperado, >/+ = obtido). $1=arq $2=maxlinhas
difffmt(){ local f="$1" max="${2:-400}" n line c cls e
  [[ -s "$f" ]] || return 1
  n=$(wc -l < "$f")
  raw '<pre class="diff">'
  while IFS= read -r line; do
    c="${line:0:1}"
    case "$c" in '<'|'-') cls="d-old";; '>'|'+') cls="d-new";; *) cls="";; esac
    e="$(escs "$line")"
    if [[ -n "$cls" ]]; then o "<span class=\"$cls\">$e</span>"; else o "$e"; fi
  done < <(head -n "$max" "$f")
  raw "</pre>"
  (( n > max )) && raw "<p class=\"muted\">… diff truncado: $max de $n linhas.</p>"
  raw $'\n'; return 0; }

# ------------------------------------------------- lista de casos de teste ----
mapfile -t FILES < <(ls -1 "$PROBLEMTEMPLATEDIR/tests/input" 2>/dev/null)
if (( ${#FILES[@]} == 0 )); then
  mapfile -t FILES < <(cd "$wb" && ls -1 -- *-log.verdict 2>/dev/null | sed 's/-log\.verdict$//')
fi

declare -A V T M
PEAKMEM=0
for f in "${FILES[@]}"; do
  v="${VERDICT[$f]:-}"
  [[ -z "$v" && -s "$wb/$f-log.verdict" ]] && v="$(<"$wb/$f-log.verdict")"
  V["$f"]="${v:-NT}"
  T["$f"]="$(exectime_of "$f")"
  M["$f"]="$(mem_of "$f")"
  [[ -n "${M[$f]}" ]] && (( ${M[$f]} > PEAKMEM )) && PEAKMEM="${M[$f]}"
done

# ============================================================ cabeçalho =======
o "#+TITLE: Report — ${PROBLEM:-?} (${LANGUAGE:-?})"
o "#+OPTIONS: ^:nil num:nil"
o ""

# ------ tema embutido (paleta espelha web/.../stats.js e docs/html/moj-docs.css)
o "#+BEGIN_EXPORT html"
cat >> "$ORG" <<'CSS'
<style>
:root{--fg:#1f2d3d;--mut:#64748b;--ac:#1e57c4;--bd:#e3e9f2;--code:#f6f8fb;
 --v-ac:#15803d;--v-wa:#be1241;--v-tle:#9a6700;--v-re:#d94f9a;--v-ce:#7a5ada;--v-gray:#94a3b8}
*{box-sizing:border-box}
body{font:16px/1.6 -apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;color:var(--fg);max-width:1000px;margin:0 auto;padding:1.3rem 1.2rem 4rem}
h1,h2,h3,h4{line-height:1.25;margin-top:1.6rem}
h1{border-bottom:2px solid var(--bd);padding-bottom:.3rem}
h2{border-bottom:1px solid var(--bd);padding-bottom:.2rem}
a{color:var(--ac);text-decoration:none} a:hover{text-decoration:underline}
pre{background:var(--code);border:1px solid var(--bd);border-radius:8px;padding:.7rem .9rem;overflow-x:auto;font-size:.82em;line-height:1.45;white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
nav#TOC{background:#f8fafd;border:1px solid var(--bd);border-radius:8px;padding:.5rem 1rem .7rem;font-size:.92em}
nav#TOC::before{content:"Índice";font-weight:700;color:var(--mut);font-size:.8em;letter-spacing:.04em;text-transform:uppercase;display:block;margin:.1rem 0 .3rem}
nav#TOC ul{margin:.15rem 0;padding-left:1.1rem}
.banner{display:flex;align-items:baseline;gap:1rem;flex-wrap:wrap;border:1px solid var(--bd);border-left:9px solid var(--v-gray);border-radius:10px;padding:.8rem 1.1rem;margin:1rem 0;background:#fbfdff}
.banner.ac{border-left-color:var(--v-ac)} .banner.wa{border-left-color:var(--v-wa)}
.banner.tle{border-left-color:var(--v-tle)} .banner.re{border-left-color:var(--v-re)} .banner.ce{border-left-color:var(--v-ce)}
.banner .big{font-size:1.5rem;font-weight:800}
.banner .pct{font-variant-numeric:tabular-nums;color:var(--mut)}
.badge{display:inline-block;padding:.04rem .5rem;border-radius:999px;color:#fff;font-size:.76em;font-weight:700;vertical-align:middle}
.hbars{display:flex;flex-direction:column;gap:.32rem;margin:.6rem 0}
.hbar-row{display:grid;grid-template-columns:minmax(130px,30%) 1fr auto;align-items:center;gap:.55rem;font-size:.86rem}
.hbar-label{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.hbar-track{background:#eef2f8;border-radius:6px;height:.95rem;overflow:hidden}
.hbar-fill{height:100%;border-radius:6px;min-width:2px}
.hbar-val{font-variant-numeric:tabular-nums;color:var(--mut);white-space:nowrap;font-size:.82rem}
.testmap{display:flex;flex-wrap:wrap;gap:4px;margin:.6rem 0}
.testmap .cell{width:18px;height:18px;border-radius:4px;background:var(--v-gray);border:1px solid rgba(0,0,0,.10);display:block}
.testmap .cell:hover{outline:2px solid var(--ac);outline-offset:1px}
.legend{display:flex;flex-wrap:wrap;gap:.9rem;font-size:.82rem;color:var(--mut);margin:.3rem 0 .2rem}
.legend .sw{display:inline-block;width:12px;height:12px;border-radius:3px;vertical-align:middle;margin-right:.25rem}
.timing .hbar-row{grid-template-columns:minmax(130px,30%) 1fr auto}
table.cases{border-collapse:collapse;width:100%;font-size:.86rem;margin:.4rem 0}
table.cases th,table.cases td{border:1px solid var(--bd);padding:.25rem .55rem;text-align:left;vertical-align:top}
table.cases th{background:#f1f5fb}
details.test{border:1px solid var(--bd);border-radius:8px;margin:.5rem 0;padding:.1rem .7rem;background:#fff}
details.test>summary{cursor:pointer;font-weight:600;padding:.4rem 0;list-style:none}
details.test>summary::-webkit-details-marker{display:none}
details.test>summary::before{content:"▸ ";color:var(--mut)}
details.test[open]>summary::before{content:"▾ "}
details.test[open]{box-shadow:0 1px 5px rgba(0,0,0,.06)}
details.sub{margin:.45rem 0}
details.sub>summary{cursor:pointer;color:var(--mut);font-size:.86rem}
.panel-h{font-weight:700;font-size:.82rem;color:var(--mut);text-transform:uppercase;letter-spacing:.03em;margin:.7rem 0 .15rem}
.diff .d-old{color:#9b1133;background:#fdeef2;display:block}
.diff .d-new{color:#0f6b32;background:#eef7f0;display:block}
.muted{color:var(--mut);font-size:.86rem}
.tmeta{font-variant-numeric:tabular-nums;color:var(--mut);font-weight:400;font-size:.85em}
table.kv{font-size:.9rem;border-collapse:collapse} table.kv td{padding:.12rem .8rem .12rem 0}
table.kv td.k{color:var(--mut)}
</style>
CSS
o "#+END_EXPORT"
o ""

# =============================================================== RESUMO ========
o "* Resumo"
o ":PROPERTIES:"
o ":CUSTOM_ID: resumo"
o ":END:"
o ""
o "#+BEGIN_EXPORT html"

bkey="$(vkey "${SMALLRESP:-NT}")"
raw "<div class=\"banner $bkey\">"
raw "<span class=\"big\">$(escs "${FINALRESP:-$(fullname "${SMALLRESP:-NT}")}")</span>"
if (( TOTALTESTS > 0 )); then
  raw "<span class=\"pct\">$CORRECT / $TOTALTESTS testes AC · $(( CORRECT*100/TOTALTESTS ))%</span>"
fi
[[ -n "$TOTALTIME" ]] && raw "<span class=\"pct\">⏱ ${TOTALTIME}s no total</span>"
(( PEAKMEM > 0 )) && raw "<span class=\"pct\">⛁ $(mem_fmt "$PEAKMEM") de pico</span>"
raw "</div>"$'\n'

if (( ${#FILES[@]} > 0 )) && [[ "$REPORTMODE" != "ce" ]]; then
  # ---- barras de distribuição de veredictos ----
  declare -A CNT
  for f in "${FILES[@]}"; do v="${V[$f]}"; CNT[$v]=$(( ${CNT[$v]:-0} + 1 )); done
  total=${#FILES[@]}
  raw '<h3 style="margin:.4rem 0">Distribuição de veredictos</h3>'$'\n'
  raw '<div class="hbars">'$'\n'
  for v in AC "AC,PE" WA TLE RE RE_NZEC TMT UE NT; do
    c=${CNT[$v]:-0}; (( c == 0 )) && continue
    w=$(awk -v c="$c" -v t="$total" 'BEGIN{v=c/t*100; if(v<1.5)v=1.5; printf "%.1f", v}')
    raw "<div class=\"hbar-row\"><div class=\"hbar-label\">$(escs "$(fullname "$v")")</div>"
    raw "<div class=\"hbar-track\"><div class=\"hbar-fill\" style=\"width:${w}%;background:$(vcolor "$v")\"></div></div>"
    raw "<div class=\"hbar-val\">$c · $(( c*100/total ))%</div></div>"$'\n'
  done
  raw '</div>'$'\n'

  # ---- mapa de testes (1 quadrado por caso, clicável) ----
  raw '<h3 style="margin:1rem 0 .2rem">Mapa de testes</h3>'$'\n'
  raw '<div class="testmap">'$'\n'
  for f in "${FILES[@]}"; do
    v="${V[$f]}"; sl="$(slugify "$f")"; tt="$f · $(fullname "$v")"
    [[ -n "${T[$f]}" ]] && tt="$tt · ${T[$f]}s"
    raw "<a class=\"cell\" style=\"background:$(vcolor "$v")\" href=\"#test-$sl\" title=\"$(escs "$tt")\"></a>"
  done
  raw $'\n''</div>'$'\n'
  raw '<div class="legend">'
  for v in AC WA TLE RE NT; do
    raw "<span><span class=\"sw\" style=\"background:$(vcolor "$v")\"></span>$(fullname "$v")</span>"
  done
  raw '</div>'$'\n'

  # ---- gráfico de tempo de execução (top tempos quando há muitos) ----
  raw '<h3 style="margin:1rem 0 .2rem">Tempo de execução <span class="muted">(limite '"${TL_LANG}"'s)</span></h3>'$'\n'
  TIMED=(); for f in "${FILES[@]}"; do [[ -n "${T[$f]}" ]] && TIMED+=("$f"); done
  show=("${TIMED[@]}"); note=""
  if (( ${#TIMED[@]} > 50 )); then
    mapfile -t show < <(for f in "${TIMED[@]}"; do printf '%s\t%s\n' "${T[$f]}" "$f"; done | sort -rn | head -50 | cut -f2)
    note="<p class=\"muted\">mostrando os 50 mais lentos de ${#TIMED[@]} testes cronometrados.</p>"
  fi
  raw '<div class="hbars timing">'$'\n'
  for f in "${show[@]}"; do
    t="${T[$f]}"; v="${V[$f]}"; w="$(pct_of "$t")"
    col=$(awk -v t="$t" -v tl="$TL_LANG" 'BEGIN{ if(tl+0<=0)tl=1; print ((t+0)>=tl)?"#be1241":"#1e57c4" }')
    raw "<div class=\"hbar-row\"><div class=\"hbar-label\"><a href=\"#test-$(slugify "$f")\">$(escs "$f")</a></div>"
    raw "<div class=\"hbar-track\"><div class=\"hbar-fill\" style=\"width:${w}%;background:${col}\"></div></div>"
    raw "<div class=\"hbar-val\">${t}s</div></div>"$'\n'
  done
  raw '</div>'$'\n'
  [[ -n "$note" ]] && raw "$note"$'\n'

  # ---- lista de casos (índice textual, colapsável) ----
  raw '<details class="sub"><summary>Lista de casos de teste</summary>'$'\n'
  raw '<table class="cases"><thead><tr><th>#</th><th>Caso</th><th>Veredicto</th><th>Tempo</th></tr></thead><tbody>'$'\n'
  i=0; for f in "${FILES[@]}"; do
    i=$((i+1)); v="${V[$f]}"
    raw "<tr><td>$i</td><td><a href=\"#test-$(slugify "$f")\">$(escs "$f")</a></td>"
    raw "<td><span class=\"badge\" style=\"background:$(vcolor "$v")\">$(escs "$v")</span> $(escs "$(fullname "$v")")</td>"
    raw "<td>${T[$f]:-—}${T[$f]:+s}</td></tr>"$'\n'
  done
  raw '</tbody></table></details>'$'\n'
fi
o "#+END_EXPORT"
o ""

# ====================================================== ERRO DE COMPILAÇÃO =====
if [[ "$REPORTMODE" == "ce" ]]; then
  o "* Erro de compilação"
  o ":PROPERTIES:"
  o ":CUSTOM_ID: compilacao"
  o ":END:"
  o ""
  o "#+BEGIN_EXPORT html"
  raw '<p class="muted">A submissão não compilou; nenhum teste foi executado.</p>'$'\n'
  for pair in "stderr:compile.log.stderr" "stdout:compile.log.stdout" "cage-run:compile.log.cage-run"; do
    label="${pair%%:*}"; file="$wb/${pair#*:}"
    [[ -s "$file" ]] || continue
    raw "<div class=\"panel-h\">$label</div>"$'\n'
    prefile "$file" "" 400
  done
  o "#+END_EXPORT"
  o ""
fi

# ===================================================== RESULTADOS POR TESTE ====
if (( ${#FILES[@]} > 0 )) && [[ "$REPORTMODE" != "ce" ]]; then
  o "* Resultados por teste"
  o ":PROPERTIES:"
  o ":CUSTOM_ID: resultados"
  o ":END:"
  o ""
  for f in "${FILES[@]}"; do
    v="${V[$f]}"; t="${T[$f]}"; sl="$(slugify "$f")"
    open=""; [[ "$v" != "AC" && "$v" != "AC,PE" ]] && open=" open"
    o "** ${f} — $(fullname "$v")"
    o ":PROPERTIES:"
    o ":CUSTOM_ID: test-$sl"
    o ":END:"
    o ""
    o "#+BEGIN_EXPORT html"
    raw "<details class=\"test\"$open>"
    raw "<summary><span class=\"badge\" style=\"background:$(vcolor "$v")\">$(escs "$v")</span> "
    raw "$(escs "$f") <span class=\"tmeta\">"
    [[ -n "$t" ]] && raw "· ${t}s / TL ${TL_LANG}s"
    [[ -n "${M[$f]}" ]] && raw " · $(mem_fmt "${M[$f]}")"
    raw "</span></summary>"$'\n'

    if [[ "$v" == "NT" ]]; then
      raw '<p class="muted">Caso não executado (parada antecipada por erro/limite).</p>'$'\n'
    else
      # diff (saída do compare.sh)
      if [[ -s "$wb/$f-log.compare" ]]; then
        raw '<div class="panel-h">Diff (esperado × obtido)</div>'$'\n'
        difffmt "$wb/$f-log.compare" 400
      fi
      # entrada
      if [[ -s "$PROBLEMTEMPLATEDIR/tests/input/$f" ]]; then
        raw '<details class="sub"><summary>Entrada</summary>'$'\n'
        prefile "$PROBLEMTEMPLATEDIR/tests/input/$f" "" 200
        raw '</details>'$'\n'
      fi
      # stderr do programa
      if [[ -s "$wb/$f-stderr" ]]; then
        raw '<details class="sub"><summary>stderr do programa</summary>'$'\n'
        prefile "$wb/$f-stderr" "" 200
        raw '</details>'$'\n'
      fi
      # bloco CAGE (debug)
      cage=""
      for cf in log.cage-run log.timelog log.bwraptime log.bwrapexitcode; do
        [[ -s "$wb/$f-$cf" ]] && cage="y"
      done
      if [[ -n "$cage" ]]; then
        raw '<details class="sub"><summary>CAGE CONTROL DATA (debug)</summary>'$'\n'
        for cf in log.cage-run log.timelog log.bwraptime log.bwrapexitcode; do
          [[ -s "$wb/$f-$cf" ]] || continue
          raw "<div class=\"panel-h\">$cf</div>"$'\n'
          prefile "$wb/$f-$cf" "" 120
        done
        raw '</details>'$'\n'
      fi
    fi
    raw "</details>"$'\n'
    o "#+END_EXPORT"
    o ""
  done
fi

# ====================================================== AMBIENTE & LIMITES =====
o "* Ambiente & limites"
o ":PROPERTIES:"
o ":CUSTOM_ID: ambiente"
o ":END:"
o ""
o "#+BEGIN_EXPORT html"
raw '<table class="kv">'$'\n'
for kv in \
  "Problema:${PROBLEM}" "Linguagem:${LANGUAGE}" "Arquivo:${SRCBASENAME}" \
  "Toolchain:${TOOLCHAIN_VER}" "Ambiente (raiz da jaula):${TOOLCHAIN_ROOT}" \
  "Limite de tempo:${TL_LANG}s" "Veredicto final:${FINALRESP}" \
  "Rodar tudo (RUNALL):${RUNALL}" "Paralelismo:${NPROCINFO}" \
  "Host:${HOSTBT}" "Início:${STARTDATE}" "Tempo total:${TOTALTIME}s"; do
  k="${kv%%:*}"; val="${kv#*:}"; [[ -z "$val" || "$val" == "s" ]] && continue
  raw "<tr><td class=\"k\">$(escs "$k")</td><td>$(escs "$val")</td></tr>"$'\n'
done
raw '</table>'$'\n'
raw '<p class="muted">Trace bruto da execução: <code>run-trace.log</code> (no diretório de trabalho do julgamento).</p>'$'\n'
o "#+END_EXPORT"

# =============================================================== compila =======
# pandoc converte o .org -> .html auto-contido. O flag de "embutir recursos" mudou de nome
# entre versões: --self-contained (<2.19) vs --embed-resources (>=2.19). Detecta p/ não
# quebrar em pandoc antigo (ex.: 2.17 no Debian) — onde --embed-resources é "Unknown option".
# CSP no <head>: o report é aberto direto numa aba (p/ as âncoras funcionarem). Sem JS no
# report (só HTML/CSS estático, conteúdo escapado) — o CSP bloqueia scripts como defesa extra.
CSPFILE="$wb/.csp.html"
printf '%s\n' "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:\">" > "$CSPFILE"
HTML_OK=0
if command -v pandoc >/dev/null 2>&1; then
  EMBED=(--self-contained)
  pandoc --help 2>/dev/null | grep -q -- '--embed-resources' && EMBED=(--embed-resources --standalone)
  if pandoc "$ORG" -f org -t html5 -s --toc --toc-depth=2 "${EMBED[@]}" \
       --include-in-header="$CSPFILE" \
       --metadata title="Report — ${PROBLEM:-?} (${LANGUAGE:-?}) — ${FINALRESP:-}" \
       -o "$HTML" 2>> "$wb/gen-report.err" && [[ -s "$HTML" ]]; then
    HTML_OK=1
  else
    echo "gen-report: pandoc falhou (ver $wb/gen-report.err); usando fallback sem pandoc" >&2
  fi
fi
# Fallback (pandoc ausente OU falhou): o .org é ~todo HTML em blocos #+BEGIN_EXPORT html;
# monta um report.html auto-contido direto, sem depender do pandoc. Garante que SEMPRE
# exista report.html (o juiz envia este HTML ao MOJ; sem ele, não há log visível).
if [[ "$HTML_OK" != 1 || ! -s "$HTML" ]]; then
  {
    printf '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">'
    printf '%s' "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:\">"
    printf '<meta name="viewport" content="width=device-width,initial-scale=1">'
    printf '<title>Report — %s (%s) — %s</title></head><body>\n' \
      "${PROBLEM:-?}" "${LANGUAGE:-?}" "${FINALRESP:-}"
    awk '
      function flush(){ if(h!=""){ printf "<h%d id=\"%s\">%s</h%d>\n",lv,id,h,lv; h=""; id="" } }
      /^#\+BEGIN_EXPORT html/{ flush(); x=1; next }
      /^#\+END_EXPORT/{ x=0; next }
      x==1{ print; next }
      /^\*\* /{ flush(); h=substr($0,4); lv=2; next }
      /^\* /{ flush(); h=substr($0,3); lv=1; next }
      /^:CUSTOM_ID:/{ id=$2; next }
      /^:PROPERTIES:|^:END:|^#\+/{ next }
      /^[[:space:]]*$/{ next }
      { flush(); print }
      END{ flush() }
    ' "$ORG"
    printf '</body></html>\n'
  } > "$HTML"
fi
