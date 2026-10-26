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
         author:$author, tags:$tags, meta:$meta, prev:$prev}'
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
