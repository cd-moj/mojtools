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
def in_range(x, lo, hi, lo_excl=False):
    v = num(x)
    if v is None or v > hi or (v <= lo if lo_excl else v < lo):
        return None
    return float(v)

# ---- tempo: o MÉTODO do TL do pacote (TLMETHOD, cdmoj/docs/PACOTE.md "Métodos de TL") ----
tl = d.get("tl") or {}
kat = d.get("kattis") or {}
if (d.get("tl_method") or "moj") == "kattis":
    # Kattis: os parâmetros do conf (KATTIS_*) viram os do problem.yaml; ausente = o padrão da spec (2.0/1.5/1.0).
    # Nenhum time_limit calculado: o Kattis o infere das submissions (a spec prefere assim). O TL é POR
    # LINGUAGEM no MOJ e único no Kattis — o por-linguagem não sobrevive à ida (fica no .kattis.json).
    tm = {}
    a = in_range(kat.get("ac_to_time_limit"), 1, 100)
    b = in_range(kat.get("time_limit_to_tle"), 1, 100)
    r = in_range(kat.get("time_resolution"), 0, 10, lo_excl=True)
    if a is not None: tm["ac_to_time_limit"] = a
    if b is not None: tm["time_limit_to_tle"] = b
    if tm: limits["time_multipliers"] = tm
    if r is not None: limits["time_resolution"] = r
else:
    # MOJ (como sempre): o TL legado do `tl` do pacote (o máx dos por-linguagem) e o calibrafactor como multiplicador
    tlvals = [v for v in tl.values() if isinstance(v, (int, float))]
    if tlvals:
        import math
        limits["time_limit"] = math.ceil(max(tlvals) * 100) / 100.0
        limits["time_resolution"] = 0.01
    cf = (d.get("calibrafactor") or "").strip()
    if cf:
        # só se for número simples (o "0.2+1.5" do bc não tem equivalente); senão omite (default 2.0)
        try:
            v = float(eval(cf, {"__builtins__": {}})) if re.fullmatch(r"[0-9.+\-*/() ]+", cf) else None
            if v and v >= 1:
                limits.setdefault("time_multipliers", {})["ac_to_time_limit"] = v
        except Exception:
            pass
# O TL FIXADO pelo autor (TLOVERRIDE[default], final nos dois métodos) é o `time_limit` do Kattis e vence o
# legado. A spec exige múltiplo de time_resolution: se não for, a resolução vira 0.01 — o TL do autor não muda.
ovd = num((d.get("tloverride") or {}).get("default"))
if ovd is not None and ovd > 0:
    res = limits.get("time_resolution", 1.0)
    if abs(round(ovd / res) * res - ovd) > 1e-9:
        limits["time_resolution"] = 0.01
    limits["time_limit"] = ovd

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
