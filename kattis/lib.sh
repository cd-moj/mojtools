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

# kt_collect <pkgdir> <id> -> JSON com os campos-fonte do MOJ (source do conf+tl, meta, author, tags)
kt_collect(){
  local pkg="$1" id="$2"
  ( set +e +u; set +o noglob
    declare -A TLMOD ULIMITS TL
    PUBLIC=""; ALLOWPARALLELTEST=""; CALIBRATIONTL=""; MAXPARALLELTESTS=""
    [[ -f "$pkg/conf" ]] && source "$pkg/conf" 2>/dev/null
    [[ -f "$pkg/tl" ]] && source "$pkg/tl" 2>/dev/null
    local tlj='{}' k
    for k in "${!TL[@]}"; do tlj="$(jq -c --arg k "$k" --argjson v "${TL[$k]:-0}" '.+{($k):$v}' <<<"$tlj" 2>/dev/null || echo "$tlj")"; done
    local ulj='{}'
    for k in "${!ULIMITS[@]}"; do ulj="$(jq -c --arg k "$k" --arg v "${ULIMITS[$k]}" '.+{($k):$v}' <<<"$ulj")"; done
    local tmj='{}'
    for k in "${!TLMOD[@]}"; do tmj="$(jq -c --arg k "$k" --arg v "${TLMOD[$k]}" '.+{($k):$v}' <<<"$tmj")"; done
    local tags='[]'; [[ -f "$pkg/tags" ]] && tags="$(sed 's/^#//' "$pkg/tags" | jq -R . | jq -sc 'map(select(length>0))')"
    local meta='{}'; [[ -f "$pkg/.moj-meta.json" ]] && meta="$(cat "$pkg/.moj-meta.json" 2>/dev/null)"; [[ -n "$meta" ]] || meta='{}'
    local prev='{}'; [[ -f "$pkg/.kattis.json" ]] && prev="$(cat "$pkg/.kattis.json" 2>/dev/null)"; [[ -n "$prev" ]] || prev='{}'
    jq -n --arg id "$id" --arg cf "${TLMOD[calibrafactor]:-}" --argjson tl "$tlj" --argjson ul "$ulj" \
      --argjson tlmod "$tmj" --arg public "${PUBLIC:-}" --arg parallel "${ALLOWPARALLELTEST:-}" \
      --arg author "$(head -1 "$pkg/author" 2>/dev/null)" --argjson tags "$tags" \
      --argjson meta "$meta" --argjson prev "$prev" \
      '{id:$id, calibrafactor:$cf, tl:$tl, ulimits:$ul, tlmod:$tlmod, public:$public,
        allowparallel:$parallel, author:$author, tags:$tags, meta:$meta, prev:$prev}'
  )
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
