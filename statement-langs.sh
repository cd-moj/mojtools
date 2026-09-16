#!/bin/bash
#This file is part of CD-MOJ. GPLv3+. See <http://www.gnu.org/licenses/>.

# statement-langs.sh — FONTE ÚNICA dos idiomas do enunciado de um pacote (sourceável).
#
# Formato (cdmoj/docs/PACOTE.md §"Idiomas"):
#   docs/enunciado.md            PT, obrigatório (também .org/.tex, legado — só p/ PT)
#   docs/enunciado.<lang>.md     tradução; <lang> ∈ STMT_LANGS_ALL (só markdown)
#   docs/notes/<sample>.<lang>.md  explicação traduzida do exemplo; ausente => cai na PT
#   docs/solucao.<lang>.md       editorial traduzido (não vai ao aluno; caderno de editorial)
#   .moj-meta.json titles{<lang>: título}  título da tradução; ausente => display_title
#
# Usado por gen-problem-json.sh, validate-problem.sh e pelo cdmoj (preview.sh, lib/problems.sh,
# lib/contest-docs.sh). Quem lista/procura arquivo de enunciado por idioma chama ESTAS funções —
# nunca reescreva o glob inline (eram 4 descobertas independentes antes de 2026-09-15).
#
#   stmt_langs_all                    -> "pt en es"
#   stmt_lang_ok <lang>               -> 0 se <lang> está na allowlist
#   stmt_file <pkg> <lang>            -> caminho do enunciado do idioma ("" se não existe)
#   stmt_fmt <arquivo>                -> md|org|tex pela extensão
#   stmt_langs_of <pkg>               -> idiomas com arquivo, PT primeiro, na ordem de STMT_LANGS_ALL
#   stmt_note_file <pkg> <sample> <lang> -> nota do exemplo no idioma, com fallback PT ("" se nenhuma)
#   stmt_label <lang> <chave>         -> rótulo fixo dos exemplos (examples|input|output|note)
#   stmt_html_lang <lang>             -> valor do atributo <html lang=…>
#   stmt_samples_html <pkg> <lang> [samples...] -> HTML da seção de exemplos (stdout)
#   stmt_title <pkg> <lang>           -> titles[lang] // display_title // "" (do .moj-meta.json)

: "${STMT_LANGS_ALL:=pt en es}"
: "${SAMPLE_LIMIT:=2}"

stmt_langs_all(){ printf '%s' "$STMT_LANGS_ALL"; }
stmt_lang_ok(){ case " $STMT_LANGS_ALL " in *" $1 "*) return 0;; *) return 1;; esac; }

stmt_file(){ # <pkg> <lang>
  local pkg="$1" lang="${2:-pt}" e
  if [[ "$lang" == pt ]]; then
    for e in md org tex; do [[ -f "$pkg/docs/enunciado.$e" ]] && { printf '%s' "$pkg/docs/enunciado.$e"; return 0; }; done
    [[ -f "$pkg/enunciado.md" ]] && { printf '%s' "$pkg/enunciado.md"; return 0; }   # legado: na raiz
  else
    stmt_lang_ok "$lang" || return 1
    [[ -f "$pkg/docs/enunciado.$lang.md" ]] && { printf '%s' "$pkg/docs/enunciado.$lang.md"; return 0; }
  fi
  return 1
}

stmt_fmt(){ case "$1" in *.org) printf org;; *.tex) printf tex;; *) printf md;; esac; }

stmt_langs_of(){ # <pkg> -> "pt en" (uma linha, separado por espaço; PT sempre que existir)
  local pkg="$1" l out=""
  for l in $STMT_LANGS_ALL; do stmt_file "$pkg" "$l" >/dev/null 2>&1 && out+="${out:+ }$l"; done
  printf '%s' "$out"
}

stmt_note_file(){ # <pkg> <sample> <lang> -> arquivo da nota (idioma > PT), "" se nenhuma
  local pkg="$1" s="$2" lang="${3:-pt}"
  if [[ "$lang" != pt && -f "$pkg/docs/notes/$s.$lang.md" ]]; then printf '%s' "$pkg/docs/notes/$s.$lang.md"; return 0; fi
  [[ -f "$pkg/docs/notes/$s.md" ]] && { printf '%s' "$pkg/docs/notes/$s.md"; return 0; }
  return 1
}

stmt_label(){ # <lang> <chave>
  case "$1:$2" in
    pt:examples) printf 'Exemplos';;    en:examples) printf 'Examples';;    es:examples) printf 'Ejemplos';;
    pt:input)    printf 'Entrada';;     en:input)    printf 'Input';;       es:input)    printf 'Entrada';;
    pt:output)   printf 'Saída';;       en:output)   printf 'Output';;      es:output)   printf 'Salida';;
    pt:note)     printf 'Explicação';;  en:note)     printf 'Explanation';; es:note)     printf 'Explicación';;
    # `%s` são placeholders p/ o printf do CHAMADOR (tamanho mostrado, tamanho real): `printf '%s'` os preserva
    pt:truncated) printf '%s' 'Exemplo grande: mostrando %s de %s — baixe o arquivo inteiro pelo botão Exemplos.';;
    en:truncated) printf '%s' 'Large sample: showing %s of %s — download the whole file with the Samples button.';;
    es:truncated) printf '%s' 'Ejemplo grande: mostrando %s de %s — descargue el archivo completo con el botón Ejemplos.';;
    *) printf '%s' "$2";;
  esac
}

stmt_html_lang(){ case "$1" in en) printf 'en';; es) printf 'es';; *) printf 'pt-BR';; esac; }

stmt_title(){ # <pkg> <lang> -> título do idioma (titles[lang] // display_title), "" se meta ausente
  local meta="$1/.moj-meta.json" lang="${2:-pt}"
  [[ -f "$meta" ]] || return 0
  jq -r --arg l "$lang" '(if $l != "pt" then (.titles[$l] // "") else "" end) as $t
    | if $t != "" then $t else (.display_title // "") end' "$meta" 2>/dev/null
}

_stmt_esc(){ sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# stmt_samples_html <pkg> <lang> [sample...] — o ÚNICO gerador do HTML dos exemplos (o gen-problem-json
# e o preview do editor chamam isto; antes cada um tinha o seu e divergiam em h3×h4). Sem a lista de
# samples: a seleção é de `stmt_sample_names` (arquivo `samples` > tests/input/sample* > primeiros SAMPLE_LIMIT).
# A nota vem de stmt_note_file (idioma > PT) e passa pelo pandoc com resource-path em docs/ (figura na
# nota funciona como no enunciado). Rótulo "Explicação" só quando há nota. Vazio se não há par input/output.
# stmt_sample_names <pkg> — A SELEÇÃO dos exemplos, um nome por linha (fonte única: o HTML dos
# exemplos E o campo `samples` do json servível saem DAQUI — por construção o dado exposto é o
# mesmo conjunto que o enunciado já mostra; teste oculto nunca entra). Ordem: arquivo `samples` ›
# tests/input/sample* (ls -1v) › primeiros SAMPLE_LIMIT de tests/input (legado sem `sample*`).
stmt_sample_names(){
  local pkg="$1"
  if [[ -f "$pkg/samples" ]]; then grep -vE '^[[:space:]]*$' "$pkg/samples"
  elif compgen -G "$pkg/tests/input/sample*" >/dev/null 2>&1; then (cd "$pkg/tests/input" && ls -1v sample* 2>/dev/null)
  else ls -1 "$pkg/tests/input" 2>/dev/null | head -n "$SAMPLE_LIMIT"; fi
  return 0
}
# stmt_samples_json <pkg> — [{name,input,output}] dos exemplos (texto cru, bytes preservados —
# jq --rawfile), só os pares com input E output, na mesma seleção do HTML. É o que /treino/problem
# e /contest/samples servem (botão ⬇ Exemplos e `moj-comp samples`). Vazio = [].
# Tetos (2026-09-16 — um sample de 214 MB virou um json de 856 MB servido a anônimos):
#   STMT_SAMPLE_MAX_BYTES      (256 KB) — o HTML mostra só o começo + aviso (label `truncated`);
#   STMT_SAMPLE_JSON_MAX_BYTES (4 MB)   — acima disso o json leva {name,size,too_big:true} sem os bytes
#                                          (o botão Exemplos e o moj-comp pulam com aviso).
: "${STMT_SAMPLE_MAX_BYTES:=262144}"
: "${STMT_SAMPLE_JSON_MAX_BYTES:=4194304}"
_stmt_fsize(){ stat -c%s "$1" 2>/dev/null || wc -c < "$1"; }
_stmt_human(){ local b="$1"; if (( b >= 1048576 )); then printf '%d MB' $(( b / 1048576 )); elif (( b >= 1024 )); then printf '%d KB' $(( b / 1024 )); else printf '%d B' "$b"; fi; }
stmt_samples_json(){
  local pkg="$1" s in out acc si so; acc="$(mktemp)"; : > "$acc"
  while IFS= read -r s; do
    [[ -n "$s" && "$s" != */* ]] || continue
    in="$pkg/tests/input/$s"; out="$pkg/tests/output/$s"
    [[ -f "$in" && -f "$out" ]] || continue
    si="$(_stmt_fsize "$in")"; so="$(_stmt_fsize "$out")"
    if (( si > STMT_SAMPLE_JSON_MAX_BYTES || so > STMT_SAMPLE_JSON_MAX_BYTES )); then
      jq -cn --arg n "$s" --argjson sz "$(( si + so ))" '{name:$n, size:$sz, too_big:true}' >> "$acc"
    else
      jq -cn --arg n "$s" --rawfile i "$in" --rawfile o "$out" '{name:$n, input:$i, output:$o}' >> "$acc"
    fi
  done < <(stmt_sample_names "$pkg")
  jq -cs '.' "$acc" 2>/dev/null || echo '[]'
  rm -f "$acc"; return 0
}
stmt_samples_html(){
  local pkg="$1" lang="${2:-pt}"; shift 2 || shift $#
  local -a S=("$@")
  (( ${#S[@]} == 0 )) && mapfile -t S < <(stmt_sample_names "$pkg")
  local notesf="$pkg/docs/sample-notes.json" s in out note nf nh i=0 n=0 body="" sa
  local l_in l_out l_note l_tr; l_in="$(stmt_label "$lang" input)"; l_out="$(stmt_label "$lang" output)"; l_note="$(stmt_label "$lang" note)"; l_tr="$(stmt_label "$lang" truncated)"
  # _blk <arquivo> <kind>: o <pre> (cortado em STMT_SAMPLE_MAX_BYTES) + o aviso DEPOIS do </pre> —
  # o botão Copiar da web casa `h3+pre`; o texto copiado nunca leva o aviso
  _blk(){ local f="$1" k="$2" sz; sz="$(_stmt_fsize "$f")"
    printf '<pre data-sample="%s" data-kind="%s">' "$sa" "$k"; head -c "$STMT_SAMPLE_MAX_BYTES" "$f" | _stmt_esc; printf '</pre>'
    (( sz > STMT_SAMPLE_MAX_BYTES )) && printf '<p class="moj-exemplo-trunc">'"$l_tr"'</p>' "$(_stmt_human "$STMT_SAMPLE_MAX_BYTES")" "$(_stmt_human "$sz")"
    return 0; }
  for s in "${S[@]}"; do
    in="$pkg/tests/input/$s"; out="$pkg/tests/output/$s"
    if [[ -f "$in" && -f "$out" ]]; then
      # data-sample/data-kind: o gancho do botão "Copiar" da web (só marcação; o nome saneado p/ atributo)
      sa="${s//[^A-Za-z0-9._-]/_}"
      body+="<div class=\"moj-exemplo\"><h3>$l_in</h3>$(_blk "$in" input)"
      body+="<h3>$l_out</h3>$(_blk "$out" output)"
      note=""
      if nf="$(stmt_note_file "$pkg" "$s" "$lang")"; then note="$(cat "$nf")"
      elif [[ -f "$notesf" ]]; then note="$(jq -r --argjson k "$i" '.[$k] // ""' "$notesf" 2>/dev/null)"; fi   # legado, por índice
      if [[ -n "$note" ]]; then
        nh="$(printf '%s' "$note" | pandoc -f markdown -t html --embed-resources --resource-path="$pkg/docs" 2>/dev/null)"
        [[ -n "$nh" ]] || nh="<p>$(printf '%s' "$note" | _stmt_esc)</p>"
        body+="<div class=\"moj-exemplo-nota\"><h3>$l_note</h3>$nh</div>"
      fi
      body+="</div>"; (( n++ ))
    fi
    (( i++ ))
  done
  [[ -n "$body" ]] && printf '<section class="moj-exemplos"><h2>%s</h2>%s</section>' "$(stmt_label "$lang" examples)" "$body"
  STMT_SAMPLES_N="$n"
  return 0
}
