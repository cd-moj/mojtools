# mojtools/kattis — interoperabilidade com o formato ICPC/Kattis (2025-09)

Conversores entre o pacote do MOJ e o **problem package format do ICPC/Kattis**
(spec 2025-09). Estratégia: **interoperar agora** (export/import) sem reescrever o juiz;
o formato nativo do MOJ converge depois. Requer `python3`+`pyyaml`; `uuidgen` opcional.

## Export (MOJ → ICPC)  ✅ pronto
```bash
bash kattis/export.sh <pkgdir> <id> <out-dir | out.tar.gz>
# ex.: kattis/export.sh moj-problems/eda2-problems/somaab "eda2-problems#somaab" /tmp/somaab.tar.gz
```
Gera um pacote Kattis válido:
- `problem.yaml` — de `conf`+`.moj-meta.json`+`author`+`tags`+`tl` (uuid v5 estável; `time_limit`
  = máx dos TL por-linguagem, arredondado p/ múltiplo de `time_resolution`; `credits.authors`,
  `keywords`, `limits`).
- `statement/problem.<lang>.md` — `docs/enunciado.md` (ou org/tex → md via pandoc).
- `data/sample` + `data/secret` — `tests/input|output` → `N.in`/`N.ans` (promove o 1º caso a
  sample se não houver `sample*`).
- `submissions/{accepted,wrong_answer,time_limit_exceeded}` — `sols/{good+pass,wrong,slow}`
  (`pass` → `accepted` com `use_for_time_limit:false`).
- `output_validator/` — se houver `scripts/compare.sh` (bridge p/ a interface Kattis 42/43).
- `input_validators/accept_all/` — trivial (o Kattis exige; **escreva um real p/ rigor ICPC**).
- `.kattis.json` — sidecar de round-trip (uuid, TLs por-linguagem, calibrafactor, checker custom).

Na plataforma: `GET /problems/export?id=<id>`, botão **⬇ ICPC** na gestão, e `moj export <id>`.
Opcional: rode `verifyproblem` (problemtools) no pacote gerado p/ certificar rigor ICPC.

## Import (ICPC → MOJ)  ✅ pronto
```bash
bash kattis/import.sh <pacote (dir|.tar[.gz/.bz2/.zst]|.zip)> <out-pkgdir>
```
`problem.yaml`→`conf`+`tl` (restaura TLs por-linguagem do `.kattis.json`), `statement/`→`docs/
enunciado`, `data/`→`tests/` (achata grupos), `submissions/`→`sols/`. O `output_validator/`
Kattis vira `scripts/compare.sh` via `validator-bridge.sh` (mapeia exit 42/43 → 4=AC/6=WA),
rodando no juiz do MOJ **sem mexer no `build-and-test.sh`** (validadores testlib/C++ exigem g++).
Na plataforma: `POST /problems/import`, botão **⬆ Importar ICPC**, e `moj import <arq> <pasta>`.

## Convergência (Fase 3)  ✅ tools prontas
- `kattis/sidecar.sh <pkg> <id>` — escreve `problem.yaml`+`.kattis.json` DENTRO do pacote MOJ
  (Kattis-aware; idempotente, uuid estável). **Chamado no create/edit/upload** → todo problema
  novo já é um pacote Kattis válido (e o import preserva o `problem.yaml` original).
- `kattis/normalize.sh <kattis-pkg> <viewdir>` — VIEW efêmera (symlinks) no layout MOJ de um
  pacote **Kattis-nativo**, p/ o juiz rodar sem importar. (Próximo passo: o juiz resolver pacotes
  Kattis-nativos via normalize; e o editor web ler/escrever o layout Kattis — incremental.)

## Não-1:1 (decisões)
- **TL por linguagem**: o Kattis tem UM `time_limit`; o export usa o máx e preserva os
  por-linguagem em `.kattis.json` (sem perda no round-trip MOJ→Kattis→MOJ).
- **Org-mode**: convertido p/ md no export (o Kattis só aceita tex/md/pdf).
- **Governança** (dono/público/coleções): fica em `.moj-meta.json`, fora do `problem.yaml`.
- **Scoring/`summary.sh`/interativo**: marcados p/ curadoria (sem mapeamento automático 100%).
