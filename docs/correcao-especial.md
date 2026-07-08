# Correção especial de problemas (scripts/ por problema)

Parte **técnica do corretor**: como um problema customiza a compilação, a execução e a
comparação. Isto **não** vai no enunciado nem no editorial (`docs/solucao.md`) — o editorial
explica a **ideia da solução**; aqui fica a mecânica.

`build-and-test.sh` procura, **por problema**, antes dos defaults de `lang/<lang>/`:

| Arquivo no pacote | Sobrepõe | Papel |
|---|---|---|
| `scripts/<lang>/compile.sh` | `lang/<lang>/compile.sh` | compilação/empacotamento; deve ecoar `BIN=<algo>` |
| `scripts/<lang>/run.sh`     | `lang/<lang>/run.sh`     | execução (raro customizar; base do INTERATIVO) |
| `scripts/<lang>/prep.sh`    | `lang/<lang>/prep.sh`    | **sourced NO HOST** antes de compilar, com `$1=$workdir`: pode `cp` arquivos p/ o workdir (aparecem em `/tmp/dir` na run) e/ou somar `EXTRABINDINGS+=" -b <path>"`. Exige bit **+x**; nunca `exit` (use `return`) |
| `scripts/compare.sh` (ou `scripts/<lang>/compare.sh`) | `lang/compare.sh` | comparador de saída |
| `scripts/summary.sh` | scorer padrão (`tests/score`/% de testes) | sourced no FIM do julgamento; pode sobrescrever `FINALRESP`/`SCORE`/`SCORE_KIND` (base do ranking interativo) |

Regras gerais:

- **`chmod +x` obrigatório** em todo `scripts/*.sh` — `cage-run.sh` executa o script direto
  (`is no executable` ⇒ Compilation Error em tudo).
- **Transporte:** `moj push` **não** carrega `scripts/`. Use `moj upload <id> <tar.gz>` (sobe o
  pacote inteiro). Publicar **por último** (um `upload` posterior reverte `public` se o
  `.moj-meta.json` do tar tiver `public:false`).
- **Checksum:** `tl-checksum.sh` inclui `scripts/*` (conteúdo + bit +x); mudar um driver/comparador
  invalida o cache do juiz e dispara recalibração.
- **Comparador (contrato):** recebe `$1 saída_do_time $2 saída_esperada $3 entrada`; `exit 4` = AC,
  `5` = AC/PE, `6` = WA.

## Submissão de função (aluno entrega só a função)

`scripts/<lang>/compile.sh` injeta um `main`/wrapper que lê a entrada, chama a função do aluno e
imprime o retorno. A fonte do aluno mantém o basename no workdir (`/tmp/rwdir`); em Java a
submissão é sempre `Main.java`. Convenção: **mesmo nome de função nas 5 linguagens** (Rust com
`#![allow(non_snake_case)]`), só mudando os tipos na assinatura.

- **C/C++:** grava `__judge_main.{c,cpp}` (protótipo + `main`) no workdir; `Makefile` compila
  **todos** os `*.c`/`*.cpp` juntos em `main` (`@echo BIN=main`).
- **Python:** concatena a fonte do aluno + um *driver tail* em `__judge_run.py`; `echo BIN=__judge_run.py`.
- **Rust:** `__judge_run.rs` faz `include!("<aluno>.rs")` + `fn main(){…}`; `rustc … -o main && echo BIN=main`
  (compila só o `__judge_run.rs`, não o glob default).
- **Java:** classe **`Judge`** separada (não `Main`, que é a do aluno) com `main` chamando
  `Main.<metodo>(...)`; `javac *.java && echo BIN=Judge.class`. Use `Integer.parseInt`/`Double.parseDouble`
  e `Locale.US` no `printf` (evita o decimal-vírgula do locale pt_BR).

## Proibir funções da biblioteca (forçar implementação na mão)

`scripts/<lang>/compile.sh` faz um `grep` na fonte do aluno **antes** de compilar e, se achar a
função proibida, ecoa a mensagem em stderr e `exit 1` (sem `BIN=` ⇒ Compilation Error). Padrão
único para as 5 linguagens (troca-se a lista por problema):

```sh
grep -qE '(^|[^[:alnum:]_])(exp|exp2|expm1)[[:space:]]*\(' "$STU"
```

Pega `exp(`, `math.exp(`, `.exp()`, `Math.exp(`; **não** pega `exp_natural` (o `_` quebra a
borda `\b`). É checagem textual — não é à prova de tudo (ofuscação, ponteiro de função), mas cobre
o caso comum. Inclua uma `sols/wrong/cheat-*.{c,py3}` que **usa** a função proibida para a
calibração confirmar que o ban a rejeita.

## Comparador com tolerância de ponto flutuante

`scripts/compare.sh` reutilizável (ε absoluto, token a token, via `awk` — locale-independente),
para problemas de saída real em que linguagens diferentes acumulam erro de ponto flutuante de
formas distintas (comparação exata falharia entre linguagens). Ver o usado em
`exponencial_natural` (ε = 10⁻³).

## Problema interativo (normalizado)

Solução conversa com um **árbitro** por stdin/stdout dentro da jaula. O pacote leva o
árbitro (`scripts/arbitro.{cpp,py,sh}`) e o **driver comum** do mojtools
(`scripts/c/{prep,run}.sh` + symlinks p/ as demais linguagens), instalados por:

```sh
bash mojtools/interactive/install-interactive.sh <pacote> arbitro.cpp [--score]
```

Protocolo: árbitro recebe o teste em `argv[1]`; a ÚLTIMA linha do stderr dele é o
RESULTADO (`WRONG <motivo>` ⇒ WA; score/info ⇒ AC, somável com `--score` p/ ranking);
sem resultado ⇒ RTE (jogador morreu) ou UE. Guia completo com exemplos:
**[`problema-interativo.md`](problema-interativo.md)**; técnico:
`mojtools/interactive/README.md`.

## Checker testlib (normalizado)

Para checkers em C++ com a [testlib](https://github.com/MikeMirzayanov/testlib) (padrão
Codeforces/Polygon — múltiplas respostas válidas, tolerância, validação contra a entrada),
o pacote leva só o **fonte** (`scripts/checker.cpp`, testlib PADRÃO, sem `-DBOCA_SUPPORT`)
e a **bridge** `scripts/compare.sh` instalada por:

```sh
bash mojtools/testlib/install-checker.sh <pacote> checker.cpp
```

A bridge compila o checker no juiz sob demanda (cache fora de `scripts/`, não polui o
tl-checksum) contra a testlib **vendorada** (`mojtools/testlib/testlib.h`) e mapeia os
exit codes: `_ok`⇒Accepted; `_wa`/`_pe`/eof⇒Wrong Answer (o `_pe` da testlib é "formato
inválido" = resposta errada — NÃO é o `AC,PE` do MOJ); `_fail`/`quitp`⇒erro de juiz.
**Nunca commite o binário do checker** (o padrão antigo de ELF de 2.7MB em
`scripts/compare.sh` está deprecado — o `validate-problem` avisa). Guia completo de
autoria com receitas: **[`checker-testlib.md`](checker-testlib.md)**; detalhes técnicos:
`mojtools/testlib/README.md`.

## Calibração de Java (operacional)

Todos os juízes declaram `java`, mas algum host pode ter o `javac` quebrado (ex.: `macalan`) e
ainda assim abocanhar o job genérico do `moj calibrate` (1 job por checksum) — aí o Java nunca
calibra. Mire os hosts com JDK real:

```sh
curl -sk -X POST "$MOJ_URL/api/v1/problems/request-calibration" \
  -H "Authorization: Bearer $(cat ~/.config/moj/token)" -H 'Content-Type: application/json' \
  -d '{"id":"apc#<prob>","hosts":["cpu1","cpu2","orval"]}'
```

O TL servível é o **máx entre hosts**, então o host de javac quebrado é inofensivo assim que um
host bom reporta.
