# mojtools/interactive — driver comum de PROBLEMA INTERATIVO

Infra normalizada para problemas em que a solução do aluno **conversa com um árbitro**
por stdin/stdout dentro da jaula. **Tutorial de autoria (comece por aqui):
[`docs/problema-interativo.md`](../docs/problema-interativo.md).**

| arquivo | vira no pacote | papel |
|---|---|---|
| `run.sh` | `scripts/c/run.sh` (+ symlinks `scripts/<lang> -> c`) — **CÓPIA REAL** (entra na JAULA) | roda árbitro+jogador cruzados por FIFOs (`stdbuf -oL`, `/bin/time` nos dois), materializa o RESULTADO em `/tmp/out`, trata TL (TERM), RTE e crash do árbitro. Driver ÚNICO — dispatch por extensão do `$BIN` (compilados, `.py`, `.sh`; melhor esforço `.js`/`.class`). |
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
| árbitro morto por SINAL | **UE** (resultado invalidado — erro do juiz/setter) |
| tempo medido > TL | **TLE** (o juiz manda TERM; driver sai 0 com o parcial) |

## Limitações v1

- Dispatch de jogador TESTADO: compilados (ELF), `py`, `sh`; melhor esforço `js`, `java`;
  `kt`/`riscv`/`spim`/`apl` sem dispatch — restrinja as linguagens do problema
  (`problem-langs`) às suportadas.
- **TL e memória INCLUEM o árbitro** (mesmo cgroup/tempo real): calibre com folga
  (`TLMOD[calibrafactor]`, `CALIBRATIONTL`) e lembre disso ao definir `MEMLIMITMB`.
- Score contínuo só via `summary.sh` (`--score`); por teste o veredicto é binário.
- Linguagem SEM o driver julga NÃO-interativamente (errado em silêncio) — por isso o
  instalador cobre todas as linguagens de `mojtools/lang/` por default.
