# mojtools/interactive — driver comum de PROBLEMA INTERATIVO

Infra normalizada para problemas em que a solução do aluno **conversa com um árbitro**
por stdin/stdout dentro da jaula. **Tutorial de autoria (comece por aqui):
[`docs/problema-interativo.md`](../docs/problema-interativo.md).**

| arquivo | vira no pacote | papel |
|---|---|---|
| `run.sh` | `scripts/c/run.sh` (+ symlinks `scripts/<lang> -> c`) — **CÓPIA REAL** (entra na JAULA) | roda árbitro+jogador cruzados por FIFOs (`stdbuf -oL`, `/bin/time` nos dois), materializa o RESULTADO em `/tmp/out`, trata TL (TERM), RTE, SIGPIPE do árbitro (= jogador sumiu ⇒ RTE/WA, nunca UE) e crash real do árbitro (UE). Regressão: `test-driver.sh` (matriz de 13 casos; rodar em dev/container, usa /tmp fixo). Driver ÚNICO — dispatch por extensão do `$BIN` (compilados, `.py`, `.sh`; melhor esforço `.js`/`.class`). |
| `prep.sh` | `scripts/c/prep.sh` = **STUB** (`prep-stub.sh`; roda no HOST) | materializa `$workdir/arbitro` a partir de `scripts/arbitro.{cpp,cc,py,sh}` (ou `scripts/arbitro` pronto). C++ compila com `-static` (roda dentro do rootfs) e cache em `<pkg>/.arbitro-cache/` (fora do tl-checksum; o FONTE entra no checksum), com `flock` (juiz multi-slot). Usa o `g++` do host ou — o caso normal num juiz — o da rootfs via `bwrap`, **bindando tudo sob `/tmp`** (a rootfs é `/` READ-ONLY: bindar caminho do host lá dentro é `Can't mkdir parents` ⇒ árbitro não compila ⇒ UE). Sourced — nunca `exit`. |
| `compare.sh` | `scripts/compare.sh` = **STUB** (`compare-stub.sh`; roda no HOST) | veredicto por teste a partir de `/tmp/out`: vazio ⇒ **13**=UE; última linha `WRONG …` ⇒ **6**=WA; senão ⇒ **4**=AC + ecoa `SCORE=<resultado>`. Problema pode substituir por um custom (ex.: razão contra `tests/output`, padrão fcte-delivery). |
| `summary-score.sh` | `scripts/summary.sh` = **STUB** (`summary-stub.sh`, com `--score`) | ranking: soma os `SCORE` dos testes AC; qualquer WA zera; sobrescreve `FINALRESP` (+`SCORE`/`SCORE_MAX`/`SCORE_KIND=rank`). |
| `install-interactive.sh` | — | instala tudo: `install-interactive.sh <pkg> <arbitro> [--score] [--langs "…"] [--keep-compare]` + smoke do prep. |

**Regra:** driver que roda **no HOST** vai p/ o pacote como **stub** (aponta p/ o canônico daqui —
`build-and-test.sh` exporta `MOJTOOLS_DIR`); só o que **entra na JAULA** é **cópia real**. Assim um
bug no driver se conserta em UM lugar, e não em cada pacote já empacotado (foi o que aconteceu com o
bind do `bwrap`: nasceu replicado em 198 pacotes).

## Fluxo dentro da jaula

```
          /tmp/in (teste, RO)
              │ argv[1]
        ┌─────▼──────┐   stdout ──► /tmp/fifo.out ──► stdin ┌──────────┐
        │  ÁRBITRO   │                                      │ JOGADOR  │
        │ (arbitro)  │   stdin ◄── /tmp/fifo.in ◄── stdout  │  ($BIN)  │
        └─────┬──────┘                                      └──────────┘
              │ stderr = log; ÚLTIMA linha = RESULTADO
              ▼
        /tmp/arbitro.log ──(driver materializa)──► /tmp/out ──► compare.sh
```

## Semântica de veredictos (o RESULTADO do árbitro manda)

| situação | veredicto |
|---|---|
| resultado = score/info | **Accepted** (exit do jogador é ignorado — jogo concluído) |
| resultado = `WRONG <motivo>` | **Wrong Answer** (mesmo se o jogador morreu — decisão do árbitro) |
| sem resultado + jogador morreu (non-zero/sinal) | **Runtime Error** (driver exit 3) |
| sem resultado + jogador ok | **UE** (compare exit 13 — anormal, investigar) |
| árbitro morto por **SIGPIPE** (o jogador fechou o pipe — RE clássico de aluno) | resultado explícito/`WRONG` do árbitro MANDA; senão jogador morto ⇒ **RTE**; jogador saiu 0 ⇒ **WA** sintético "encerrou sem ler a resposta" |
| árbitro morto por OUTRO sinal | **UE** (resultado invalidado — erro do juiz/setter) |
| árbitro exit ≠ 0 (contrato manda 0) | `/tmp/out`/última linha `WRONG` valem; senão jogador morto ⇒ **RTE** (fecha o AC falso do `BrokenPipeError` py); senão **UE**. Linha de log NUNCA vira resultado de árbitro anormal (não-`WRONG` ⇒ compare daria AC) |
| tempo medido > TL | **TLE** (o juiz manda TERM; driver sai 0 com o parcial) |

## Limitações v1

- Dispatch de jogador TESTADO: compilados (ELF), `py`, `sh`, **`java`** (roda a classe com
  `main`, eleita pelo `lang/java/compile.sh`) e **`kt`** (`java -jar` do jar do `kotlinc
  -include-runtime`); melhor esforço `js`; `cs`/`riscv`/`spim`/`apl`/`pl` sem dispatch —
  restrinja as linguagens do problema às suportadas.
- **JVM ignora o `stdbuf -oL`** do driver (I/O próprio): solução Java/Kotlin PRECISA de
  `System.out.flush()` a cada resposta, senão trava (TLE). Diga isso no enunciado — o
  guia de autoria tem os modelos.
- **TL e memória INCLUEM o árbitro** (mesmo cgroup/tempo real): calibre com folga
  (`TLMOD[calibrafactor]`, `CALIBRATIONTL`) e lembre disso ao definir `MEMLIMITMB`.
- Score contínuo só via `summary.sh` (`--score`); por teste o veredicto é binário.
- Linguagem SEM o driver julga NÃO-interativamente (errado em silêncio) — por isso o
  instalador cobre todas as linguagens de `mojtools/lang/` por default.
