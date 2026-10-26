# kattis/lib.sh — helpers de interoperabilidade com o formato de pacote ICPC/Kattis (2025-09).
# Mapeia conf/.moj-meta/author/tags/tl <-> problem.yaml. YAML via python3+pyyaml. Sourced.
: "${MOJ_STATEMENT_LANG:=pt-BR}"        # língua do enunciado MOJ (ISO) p/ statement/problem.<lang>.*
: "${KT_LICENSE:=unknown}"              # license default no export
: "${KATTIS_FORMAT_VERSION:=2025-09}"
KT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

have_py(){ command -v python3 >/dev/null && python3 -c 'import yaml' >/dev/null 2>&1; }

# kt_uuid <moj-id> -> UUID v5 estável (mesmo problema -> mesmo uuid)
kt_uuid(){ python3 - "$1" <<'PY'
import sys, uuid
print(uuid.uuid5(uuid.NAMESPACE_URL, "urn:moj:problem:"+sys.argv[1]))
PY
}
# kt_eval_factor <expr> -> float (avalia "2 + 0.5"/"1+1.35"; só dígitos + - * / . e espaço)
kt_eval_factor(){ python3 - "$1" <<'PY'
import sys, re
e=(sys.argv[1] or "").strip()
print("") if not e or not re.fullmatch(r"[0-9.+\-*/() ]+", e) else print(eval(e, {"__builtins__":{}}))
PY
}

# kt_conf_json <arquivo> -> {"scalars":{NOME:valor},"arrays":{NOME:{chave:valor}}}: as atribuições bash do
# arquivo (o `conf` ou o `tl` do pacote), lidas por REGEX. NUNCA `source`: o conf é texto do AUTOR e isto roda
# NA API (sidecar.sh a cada create/edit/upload de problema, e o export). Até 26/10/2026 o kt_collect fazia
# `source` do conf e do tl, e uma linha `X=$(…)` executava código no servidor com o usuário da API; aqui ela é
# texto. A última atribuição vence, como no bash; aspas simples ou duplas em volta do valor saem; depois de um
# espaço, o resto da linha (comentário) é ignorado.
kt_conf_json(){ python3 -I - "$1" <<'PY'
import sys, re, json
arrays, scalars = {}, {}
try:
    with open(sys.argv[1], encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
except OSError:
    lines = []
ASSIGN = re.compile(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)(?:\[([^\]]*)\])?=(.*)$')
def value(s):
    s = s.strip()
    if s[:1] in ('"', "'"):
        end = s.find(s[0], 1)
        return s[1:end] if end > 0 else s[1:]
    return s.split(None, 1)[0] if s else ""
for ln in lines:
    m = ASSIGN.match(ln)
    if not m:
        continue
    name, key, v = m.group(1), m.group(2), value(m.group(3))
    if key is None:
        scalars[name] = v
    else:
        arrays.setdefault(name, {})[key.strip().strip("\"'")] = v
print(json.dumps({"scalars": scalars, "arrays": arrays}, ensure_ascii=False))
PY
}

# kt_collect <pkgdir> <id> -> JSON com os campos-fonte do MOJ (conf+tl por kt_conf_json, meta, author, tags)
kt_collect(){
  local pkg="$1" id="$2" tags='[]' meta='{}' prev='{}'
  [[ -f "$pkg/tags" ]] && tags="$(sed 's/^#//' "$pkg/tags" | jq -R . | jq -sc 'map(select(length>0))')"
  [[ -f "$pkg/.moj-meta.json" ]] && meta="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$meta" ]] || meta='{}'
  [[ -f "$pkg/.kattis.json" ]] && prev="$(cat "$pkg/.kattis.json" 2>/dev/null)"; [[ -n "$prev" ]] || prev='{}'
  { kt_conf_json "$pkg/conf"; kt_conf_json "$pkg/tl"; } \
  | jq -s --arg id "$id" --arg author "$(head -1 "$pkg/author" 2>/dev/null)" --argjson tags "$tags" \
      --argjson meta "$meta" --argjson prev "$prev" '
      (.[0] // {}) as $c | (.[1] // {}) as $t
      # TL: só número, no formato do calibreitor (".310", "1"); o resto da linha não é TL
      | (($t.arrays.TL // {}) | to_entries
          | map(select(.value | test("^([0-9]+\\.?[0-9]*|\\.[0-9]+)$"))
                | .value |= ((if startswith(".") then "0" + . else . end)
                             | (if endswith(".") then . + "0" else . end) | tonumber))
          | from_entries) as $tl
      | {id:$id, calibrafactor:(($c.arrays.TLMOD // {}).calibrafactor // ""), tl:$tl,
         ulimits:($c.arrays.ULIMITS // {}), tlmod:($c.arrays.TLMOD // {}),
         public:($c.scalars.PUBLIC // ""), allowparallel:($c.scalars.ALLOWPARALLELTEST // ""),
         # método do TL (tl-methods.sh) + parâmetros do Kattis + o TL fixado pelo autor (TLOVERRIDE)
         tl_method:(if $c.scalars.TLMETHOD == "kattis" then "kattis" else "moj" end),
         kattis:{ac_to_time_limit:($c.scalars.KATTIS_AC_TO_TIME_LIMIT // ""),
                 time_limit_to_tle:($c.scalars.KATTIS_TIME_LIMIT_TO_TLE // ""),
                 time_resolution:($c.scalars.KATTIS_TIME_RESOLUTION // "")},
         tloverride:($c.arrays.TLOVERRIDE // {}),
         author:$author, tags:$tags, meta:$meta, prev:$prev}'
}

# kt_tl_conf <problem.yaml em JSON> <.kattis.json ou {}> -> as linhas de TEMPO do `conf` do MOJ (stdout), p/ o
# import e o normalize. Só NÚMERO validado vira linha (o conf é sourced no juiz). Mapeamento (cdmoj/docs/PACOTE.md
# "Métodos de TL"):
#   • TLMETHOD: o do sidecar (ida e volta MOJ → Kattis → MOJ); sem sidecar (pacote Kattis nativo) = kattis;
#   • time_multipliers.ac_to_time_limit / time_limit_to_tle (ou o legado time_multiplier / time_safety_margin)
#     e time_resolution -> KATTIS_*; o calibrafactor volta do sidecar (o multiplicador do Kattis NÃO é ele);
#   • time_limit explícito = o TL fixado pelo autor -> TLOVERRIDE[default]. Exceção: sidecar ANTIGO (sem a
#     chave `tloverride`), em que o time_limit era o máx do calibrado — aí o por-linguagem volta pelo `tl`.
#     Sidecar novo devolve o TLOVERRIDE do autor por linguagem, como era.
kt_tl_conf(){
  jq -rn --argjson y "$1" --argjson side "$2" '
    def num($lo; $hi; $excl):
      if . == null then null else (tostring) as $s
        | if ($s | test("^([0-9]+\\.?[0-9]*|\\.[0-9]+)$")) then
            ($s | (if startswith(".") then "0" + . else . end) | (if endswith(".") then . + "0" else . end) | tonumber)
            | (if ((if $excl then . > $lo else . >= $lo end) and . <= $hi) then . else null end)
          else null end end;
    ($y.limits // {}) as $l | ($l.time_multipliers // {}) as $tm
    | ($side | type == "object" and has("moj_id")) as $rt
    # ida e volta: o método e os KATTIS_* do sidecar (no método MOJ o ac_to_time_limit do yaml é o calibrafactor);
    # sidecar de antes de 26/10/2026 (sem tl_method) é de um problema MOJ
    | (if $rt then (if $side.tl_method == "kattis" then "kattis" else "moj" end) else "kattis" end) as $m
    | ((if $rt then $side.kattis.ac_to_time_limit else ($tm.ac_to_time_limit // $l.time_multiplier) end) | num(1; 100; false)) as $a
    | ((if $rt then $side.kattis.time_limit_to_tle else ($tm.time_limit_to_tle // $l.time_safety_margin) end) | num(1; 100; false)) as $b
    | ((if $rt then $side.kattis.time_resolution else $l.time_resolution end) | num(0; 10; true)) as $r
    | (($side.calibrafactor // "") | tostring) as $cf
    | (if $rt and ($side | has("tloverride")) then ($side.tloverride // {})
       elif $rt then {}
       else {default: $l.time_limit} end) as $ov
    | (if $m == "kattis" then "TLMETHOD=kattis" else empty end),
      (if ($cf | test("^[0-9][0-9.+*/ ()-]*$")) then "TLMOD[calibrafactor]=\"\($cf)\"" else "TLMOD[calibrafactor]=1.35" end),
      (if $a != null then "KATTIS_AC_TO_TIME_LIMIT=\($a)" else empty end),
      (if $b != null then "KATTIS_TIME_LIMIT_TO_TLE=\($b)" else empty end),
      (if $r != null then "KATTIS_TIME_RESOLUTION=\($r)" else empty end),
      ($ov | to_entries[] | select(.key | test("^[A-Za-z0-9]{1,16}$"))
        | (.value | num(0; 100000; true)) as $v | select($v != null) | "TLOVERRIDE[\(.key)]=\($v)")'
}

# kt_problem_yaml <collect-json> <uuid> <repo> -> escreve problem.yaml no stdout
kt_problem_yaml(){ printf '%s' "$1" | KT_FMT="$KATTIS_FORMAT_VERSION" KT_LANG="$MOJ_STATEMENT_LANG" \
  KT_LIC="$KT_LICENSE" python3 "$KT_DIR/conf2yaml.py" "$2" "$3"; }

# kt_parse_yaml <problem.yaml> -> JSON (p/ o import)
kt_parse_yaml(){ python3 - "$1" <<'PY'
import sys, yaml, json
with open(sys.argv[1]) as f: d=yaml.safe_load(f) or {}
print(json.dumps(d))
PY
}

# kt_norm_text <file> — normaliza p/ Kattis: UTF-8, LF, newline final
kt_norm_text(){ [[ -f "$1" ]] || return 0; local t; t="$(mktemp)"; sed 's/\r$//' "$1" > "$t"; [[ -s "$t" && "$(tail -c1 "$t")" != "" ]] && printf '\n' >> "$t"; mv -f "$t" "$1"; }
