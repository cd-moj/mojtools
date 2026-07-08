# mojtools — sandbox de julgamento + enunciados

Ferramentas de **julgamento** e de **enunciado/validação** de problemas. Repo git próprio
(`cd-moj/mojtools`). Roda em **dois lugares**: no **servidor** (validar/indexar problema) e em
cada **juiz** (compilar/rodar em sandbox, calibrar). Uma máquina de juiz clona só `judge` + este.
Workspace multi-repo: ver `../CLAUDE.md`.

## Scripts principais

- `cage-run.sh` — sandbox **bubblewrap** (`bwrap`). Roda do **root do host** (default) ou de um
  rootfs via `CAGE_ROOT`. `make-sysroot.sh` monta um rootfs Ubuntu com os compiladores. O
  default de `python3` é **PyPy3**. Limite de memória `-M`: root = cgroup v1 (cset); **sem root
  = cgroup v2 via `systemd-run --user --scope` (MemoryMax; degrada com aviso sem user manager)**.
  Antes de prova hostil, rode **`stress-cage.sh`** num juiz real (ver `SANDBOX.md` §Hardening).
- `build-and-test.sh <lang> <sol> <pkg> [y]` — compila + roda contra os testes; o veredicto é a
  **última linha** da saída (`FINALRESP`, ex.: `Accepted,100p` — nome + score embutido). Usa
  `lang/<lang>/run.sh` (um por linguagem, mesmo contrato). Além do stdout, grava `report.env`
  (`KEY=%q`, lido por `gen-report.sh` e pelos backends de juiz) com o veredicto **estruturado**:
  `SMALLRESP` (código curto), `FINALRESP` (display c/ score), **`VERDICT_CANON`** (nome canônico
  **limpo**, sem score — `Accepted`/`Wrong Answer`/… — p/ o backend casar o auto-veredicto),
  **`SCORE`/`SCORE_MAX`/`SCORE_KIND`** (`tests`=% de testes, `points`=soma de grupos),
  **`SCORE_GROUPS`** (grupos estruturados: JSON `[{"earned":N|null,"max":N},…]` na ordem do
  `tests/score`, só grupos de peso>0 — `earned`=peso (passou) | `0` (falhou) | `null` (não
  executado); vazio = sem grupos) e `CORRECT`/`TOTALTESTS`. O `FINALRESP`/contrato do stdout
  **não muda** (compat). O banner do `report.html` mostra o **`VERDICT_CANON`** + detalhe
  (pct de testes ou pontos/grupos).
- `gen-report.sh` — gera o `report.html` por submissão.
- `calibreitor.sh` — calibra um problema num juiz: roda as soluções, define o **TL** e reporta
  (`ensure_cached <id> [force] [full]`; `full` roda todas as soluções).
- `render-statement.sh <enunf> [fmt=md] [exemplos.html] [titulo]` — **renderizador único** do
  enunciado (pandoc standalone, `--mathml --embed-resources`). **= o "Pré-visualizar" do editor
  = o HTML servido.** Injeta `<h1 class="moj-title">` do título e remove `% Título` legado.
- `gen-problem-json.sh <pkg> [id]` — gera o índice servível do treino
  (`contests/treino/var/jsons/<id>.json`): título + autor (arquivo `author`, verbatim) + TL +
  tags + **coleções** (`.moj-meta.json` `collections`, verbatim — um problema pode estar em várias) +
  HTML (via render-statement) + exemplos (de `tests/*`, ordem `sample*`) + explicações
  (`docs/sample-notes.json`).
  **Ignora `docs/solucao.md`** (editorial não vai ao aluno).
- `validate-problem.sh <pkg> [id]` — **portão de qualidade** (relatório em
  `run/validation/<id>.json`). `ok = (map(.ok)|all)` → todo check `add` é **HARD**. Exige
  `## Entrada` e `## Saída`. Avisos *soft* em `render_warnings` (ex.: exemplo embutido no texto).
  Se passar, chama `gen-problem-json.sh`.
- **Transporte de `scripts/`**: o `moj push`/`clone` fazem round-trip COMPLETO da correção
  especial (conteúdo+`+x`+symlinks, campo `scripts_files` da API) — `moj upload <id> <dir>`
  (aceita diretório) segue como via do tar inteiro. Atalhos da CLI: `moj checker`,
  `moj interactive`, `moj test --run` (julga local via build-and-test; exige bwrap real).
- `interactive/` — **problemas INTERATIVOS normalizados**: driver comum entre linguagens
  (`run.sh` roda árbitro+jogador por FIFOs; `prep.sh` materializa o árbitro — C++ compilado
  no host com `-static` e cache FORA de `scripts/`; `compare.sh` genérico 13/6/4;
  `summary-score.sh` p/ ranking) + `install-interactive.sh <pkg> <arbitro> [--score]`.
  Protocolo: árbitro lê o teste de `argv[1]`; ÚLTIMA linha do stderr = resultado
  (`WRONG <motivo>` ⇒ WA). Guia: `docs/problema-interativo.md`; técnico: `interactive/README.md`.
- `testlib/` — **checkers testlib normalizados**: `testlib.h` vendorada + `checker-bridge.sh`
  (vai p/ o pacote como `scripts/compare.sh`; compila `scripts/checker.cpp` no juiz sob demanda,
  cache FORA de `scripts/` p/ não poluir o tl-checksum) + `install-checker.sh <pkg> <checker.cpp>`.
  Checker é testlib PADRÃO (sem `-DBOCA_SUPPORT`); mapa: `_ok`⇒AC, `_wa`/`_pe`/eof⇒WA (o `_pe`
  da testlib é "formato inválido" = errado, NÃO é o AC,PE do MOJ), `_fail`/`quitp`⇒UE. **Nunca
  commitar binário de checker** (padrão antigo deprecado; o validate avisa). Guia de autoria:
  `docs/checker-testlib.md`; técnico: `testlib/README.md`.
- `tl-checksum.sh` — checksum do pacote p/ invalidar o TL quando muda. Também é **carimbado no
  índice de donos** por `gen-problem-owners.sh` (campo `tl_checksum`, SÓ p/ problemas já calibrados
  — têm `run/tl/<id>.json`) p/ a gestão comparar com o checksum calibrado e marcar "precisa
  recalibrar" sem re-hashear pacote a cada request. O `gen-problem-owners.sh` também carimba
  **`public_at`** (epoch da 1ª publicação; do `.moj-meta.json` ou do seed
  `contests/treino/var/public-at-seed.json`) p/ o mapa de calor de entrada de públicos, e
  **`good_langs`** (extensões de `sols/good/*` = linguagens) p/ a gestão marcar "revisar" quando uma
  linguagem good não tem TL calibrado (solução good que não rodou/passou em juiz nenhum).
  **Storage MOJ-nativo (sem Gitea/LFS):** cada problema é um repo git LOCAL em
  `MOJ_PROBLEMS_DIR/<org>/<prob>`; o servidor commita direto (`problem_commit` em `cdmoj/lib/problems.sh`,
  flock por-problema). `gen-problem-owners.sh` lê o HEAD **por problema** p/ assinar o cache de
  `tl_checksum`. (O antigo `git-broker.sh`/LFS/Gitea foi removido no cut-over — ver `cdmoj`.)
  `score-summary.sh` — pontuação por grupos (o valor do problema é a **soma dos pesos**; pode
  passar de 100). Além do `FINALRESP` legado (`Wrong,60p. Pontos | 30 | 0 |…`), emite o
  **`SCORE_GROUPS`** estruturado (acima) p/ o backend servir grupos por submissão.

## Regras

- **Um renderizador só.** Mexeu no enunciado? é em `render-statement.sh` — o preview, o servido
  e a validação acompanham juntos. Não criar um pandoc paralelo.
- Exemplos do enunciado vêm **sempre** de `tests/input|output/sample*` (na ordem), nunca do texto.
- **Limites de memória/stack**: `MEMLIMITMB` (conf) decide o MLE por RSS e a **JVM dimensiona
  `-Xmx = MEMLIMITMB`** (java/kt/interativo leem `MOJ_MEMLIMITMB`/`MOJ_STACKKB` do `binfile.sh`,
  o canal p/ dentro da jaula); cgroup duro = `max(600, MEMLIMITMB+64)` (root e sem root). Stack:
  **default 128MB p/ todas as linguagens** (`ULIMITS[-s]=131072`, herdado através do bwrap);
  override por conf `STACKLIMITMB=<MB>` (vence) ou `ULIMITS[-s]=<KB>`; a JVM espelha em `-Xss`.
- `lang/<lang>/run.sh`: mesmo contrato p/ toda linguagem aceita. O tempo-limite de **compilação**
  é 30s por default; linguagem de compilador lento sobe via arquivo **`lang/<lang>/compile-tl`**
  (segundos; o problema pode sobrescrever com `scripts/<lang>/compile-tl`) — ex.: `kt` (Kotlin,
  JVM fria do kotlinc) usa 120. Kotlin no rootfs: camada própria no `sysroot/Containerfile`
  (zip da JetBrains em `/opt/kotlin`, `ARG KOTLIN_VER`); em modo host o `lang/kt/prep.sh` binda
  `/opt/kotlin` na jaula.
- **Python é UMA linguagem: `py`** (interpretador **pypy3**, fallback `python3` no modo host).
  O `lang/py/compile.sh` faz **check de sintaxe** (`py_compile`) — erro de sintaxe vira
  **Compilation Error**. `py2` foi extinto; `.py2`/`.py3` são extensões LEGADAS: `build-and-test.sh`
  e `calibreitor.sh` normalizam `py2|py3 → py` (lang-dir, chave de TL, _VERCMD), `lang/py3` é
  symlink de compat p/ `scripts/py3/` de pacotes, e o `build-and-test.sh` tem shim
  `TL[py]=TL[py3]` p/ caches `tl.<host>` calibrados antes da unificação.
- `bash -n` antes de commitar. **Não commitar `lang/apl/run.sh`** (mod local pré-existente).
- Rodapé de commit: **só** `Co-Authored-By:`, **nunca** uma linha `Claude-Session:` (ruído no histórico).
- **Doc junto com o código** (doc atrasada = bug): mudou render/formato de pacote/validação/cálculo de TL?
  atualize `cdmoj/docs/API.md` (+ `cdmoj/web/api/openapi.json` se for contrato) e os `CLAUDE.md` no mesmo commit.
  **Formato do pacote** é descrito em 4 lugares (repos diferentes) que têm de ficar em sincronia:
  `cdmoj/docs/API.md`, `cdmoj/CLAUDE.md` ("Pacote canônico"), `moj-cli/README.md` ("Pacote do problema") e
  este arquivo. Lembre: o **título** vem do campo `display_title` (o `% Título` do enunciado é legado — o
  `render-statement.sh` o remove e injeta o `<h1>` a partir do campo).
