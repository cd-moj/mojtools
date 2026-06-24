#!/usr/bin/env python3
# conf2yaml.py — monta problem.yaml (Kattis 2025-09) a partir do JSON coletado do pacote MOJ.
# stdin: JSON do kt_collect ; argv: <uuid> <repo> ; env: KT_FMT, KT_LANG, KT_LIC
import sys, os, re, json, yaml

d = json.load(sys.stdin)
uuid_ = sys.argv[1]
repo = sys.argv[2] if len(sys.argv) > 2 else ""
LANG = os.environ.get("KT_LANG", "en")
FMT = os.environ.get("KT_FMT", "2025-09")
LIC = os.environ.get("KT_LIC", "unknown")
meta = d.get("meta") or {}
prob = d["id"].split("#", 1)[-1]

def num(x):
    try:
        f = float(x); return int(f) if f == int(f) else f
    except Exception:
        return None

# título
title = meta.get("display_title") or prob

# autores (texto livre -> lista)
authors = [a.strip() for a in re.split(r"\s+e\s+|,|;|&|\band\b", d.get("author") or "") if a.strip()]

# limites
ul = d.get("ulimits") or {}
mem = num(ul.get("-v"))
memory = int(mem / 1024) if mem else 2048           # ulimit -v (KiB) -> MiB
outb = num(ul.get("-f"))
output = max(1, int(outb / 1024)) if outb else 8     # bash ulimit -f (blocos 1KiB) -> MiB

limits = {
    "compilation_time": 60, "compilation_memory": 2048,
    "memory": memory, "output": output,
    "validation_time": 60, "validation_memory": 2048, "validation_output": 8,
}
tl = d.get("tl") or {}
tlvals = [v for v in tl.values() if isinstance(v, (int, float))]
if tlvals:
    import math
    # Kattis = UM time_limit (máx dos por-linguagem), múltiplo de time_resolution.
    limits["time_limit"] = math.ceil(max(tlvals) * 100) / 100.0
    limits["time_resolution"] = 0.01
cf = (d.get("calibrafactor") or "").strip()
if cf:
    # avaliado pelo chamador? aqui só se for número simples; senão omite (default 2.0)
    try:
        v = float(eval(cf, {"__builtins__": {}})) if re.fullmatch(r"[0-9.+\-*/() ]+", cf) else None
        if v and v >= 1:
            limits.setdefault("time_multipliers", {})["ac_to_time_limit"] = v
    except Exception:
        pass

doc = {
    "problem_format_version": FMT,
    "name": {LANG: title},
    "uuid": uuid_,
    "type": "pass-fail",
    "limits": limits,
}
if authors:
    doc["credits"] = {"authors": authors}
if repo:
    doc["source"] = {"name": repo}
doc["license"] = LIC
kw = [k for k in (d.get("tags") or []) if k]
if kw:
    doc["keywords"] = kw

yaml.safe_dump(doc, sys.stdout, sort_keys=False, allow_unicode=True, default_flow_style=False)
