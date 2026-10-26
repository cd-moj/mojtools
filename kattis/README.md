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
- `problem.yaml` — de `conf`+`.moj-meta.json`+`author`+`tags`+`tl`. O `conf` e o `tl` são lidos por
  REGEX (`kt_conf_json`), nunca por `source`: isto roda na API e o conf é texto do autor. Ver
  `test-no-source.sh`. Também: uuid v5 estável; `credits.authors`, `keywords`, `limits`. O **tempo**
  segue o método do TL do pacote (`TLMETHOD`, `cdmoj/docs/PACOTE.md` "Métodos de TL"): com `kattis`,
  `time_multipliers` e `time_resolution` saem dos `KATTIS_*` e o Kattis infere o `time_limit` das
  submissions (a spec prefere assim); com `moj` (o de sempre), o `calibrafactor` vira o
  `ac_to_time_limit`. Nos dois, o TL FIXADO pelo autor (`TLOVERRIDE[default]`) é o `time_limit` — e,
  se não for múltiplo da resolução, ela vira 0.01 (o TL do autor não muda).
- `statement/problem.<lang>.md` — `docs/enunciado.md` (ou org/tex → md via pandoc).
- `data/sample` + `data/secret` — `tests/input|output` → `N.in`/`N.ans` (promove o 1º caso a
  sample se não houver `sample*`).
- `submissions/{accepted,wrong_answer,time_limit_exceeded,pass}` — `sols/{good,wrong,slow,pass}`. O `pass`
  (tem de passar, não define o TL) vai p/ um diretório PRÓPRIO com a regra `pass: {permitted: [AC]}` no
  `submissions/submissions.yaml`: no `accepted/` a regra pré-definida (`use_for_time_limit: lower`) valeria
  sempre.
- `output_validator/` — se houver `scripts/compare.sh` (bridge p/ a interface Kattis 42/43).
- `input_validators/accept_all/` — trivial (o Kattis exige; **escreva um real p/ rigor ICPC**).
- `.kattis.json` — sidecar de round-trip (uuid, TLs por-linguagem, calibrafactor, checker custom).

Na plataforma: `GET /problems/export?id=<id>`, botão **⬇ ICPC** na gestão, e `moj export <id>`.
Opcional: rode `verifyproblem` (problemtools) no pacote gerado p/ certificar rigor ICPC.

## Import (ICPC → MOJ)  ✅ pronto
```bash
bash kattis/import.sh <pacote (dir|.tar[.gz/.bz2/.zst]|.zip)> <out-pkgdir>
```
`problem.yaml`→`conf` (o tempo pelo `kt_tl_conf`: `TLMETHOD=kattis` + `time_multipliers` — ou o legado
`time_multiplier`/`time_safety_margin` — e `time_resolution` → `KATTIS_*`; `time_limit` explícito →
`TLOVERRIDE[default]`; numa ida e volta, o método, os `KATTIS_*`, o `calibrafactor` e os `TLOVERRIDE` voltam
do `.kattis.json`; só número validado vira linha), `statement/`→`docs/enunciado`, `data/`→`tests/` (achata
grupos), `submissions/`→`sols/` (`brute_force` — RTE ou TLE, nunca WA — vai p/ `upcoming`: o MOJ não tem essa
categoria). Teste: `kattis/test-kattis.sh` (`make test-kattis`). O `output_validator/`
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
- **TL por linguagem**: o Kattis tem UM `time_limit` por problema; o MOJ calibra por linguagem nos DOIS
  métodos (o Kattis do MOJ é a fórmula da spec aplicada linguagem a linguagem). O por-linguagem fica no
  `.kattis.json` (sem perda no round-trip MOJ→Kattis→MOJ), mas não sobrevive a um juiz Kattis de verdade.
- **Org-mode**: convertido p/ md no export (o Kattis só aceita tex/md/pdf).
- **Governança** (dono/público/coleções): fica em `.moj-meta.json`, fora do `problem.yaml`.
- **Scoring/`summary.sh`/interativo**: marcados p/ curadoria (sem mapeamento automático 100%).
