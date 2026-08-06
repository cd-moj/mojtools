# Montando um problema INTERATIVO no MOJ — guia de autoria

Num problema interativo a solução do aluno (o **jogador**) conversa com um **árbitro**
por stdin/stdout — o árbitro conduz o jogo, valida cada jogada e decide o resultado.
Este guia é o protocolo canônico + passo a passo. A parte técnica do driver está em
[`../interactive/README.md`](../interactive/README.md); a mecânica geral de `scripts/`
em [`correcao-especial.md`](correcao-especial.md).

> **Composição**: o interativo é dono dos slots RUN e COMPARE — NÃO compõe com checker
> testlib nem com submissão de função. Ver os 4 slots em `correcao-especial.md`.

## Componentes

```
tests/input/N      dado do ÁRBITRO (mapa, alvo, semente…) — o jogador NUNCA o vê cru
tests/output/N     PLACEHOLDER (precisa existir em par com o input; conteúdo livre —
                   um compare custom pode usá-lo, ex.: score de referência)
scripts/arbitro.*  o árbitro (você escreve — .cpp, .py ou .sh)
scripts/c/         o DRIVER comum (prep.sh + run.sh, instalados do mojtools)
scripts/<lang>     symlinks -> c (todas as linguagens; instalados automaticamente)
scripts/compare.sh veredicto por teste (genérico do protocolo; pode customizar)
scripts/summary.sh (opcional, --score) veredicto final somando scores — ranking
```

## O protocolo do árbitro

```
              /tmp/in (o teste)
                  │ argv[1]
            ┌─────▼──────┐  stdout ───────► stdin  ┌─────────┐
            │  ÁRBITRO   │                         │ JOGADOR │
            │            │  stdin  ◄─────── stdout │         │
            └─────┬──────┘                         └─────────┘
                  │ stderr = log livre
                  ▼
        ÚLTIMA linha do stderr = RESULTADO
```

Regras do árbitro:

1. **Recebe o caminho do teste em `argv[1]`** e lê o cenário DELE (nunca do stdin —
   o stdin é o jogador).
2. **Tudo que imprimir no stdout vira entrada do jogador** e vice-versa. **Sempre dê
   flush por linha** (`fflush(stdout)` no C, `flush=True` no Python; `echo` do bash já
   é por linha). Sem flush = deadlock = TLE injusto.
3. **stderr é o seu log** (aparece no report do aluno conforme a política do contest).
   A **ÚLTIMA linha do stderr é o RESULTADO**:
   - sucesso ⇒ imprima o **score** (número) ou uma informação final;
   - erro do jogador ⇒ imprima **`WRONG <motivo>`** (ex.: `WRONG clicou em bomba (10,5)`).
4. **Termine com exit 0 SEMPRE** (inclusive no WRONG — quem decide o veredicto é o
   resultado, não o exit). Crash/sinal do árbitro = erro do PROBLEMA ⇒ vira UE — com UMA
   exceção: **SIGPIPE (o jogador fechou o pipe) é erro do ALUNO**, e o driver o trata
   (RTE/WA); ainda assim, PROTEJA o árbitro (regra 5½) para dar WA com motivo.
5. **Jogador sumiu no meio** (EOF ao ler): imprima `WRONG <motivo>` e saia 0 — o aluno
   vê Wrong Answer. Se preferir que crash do jogador apareça como Runtime Error, apenas
   NÃO produza resultado (saia 0 em silêncio): o driver detecta a morte do jogador e dá RTE.
5½. **Jogador sumiu na ESCRITA** (você responde e ele já morreu — o RE mais comum de
   aluno): sem proteção o árbitro morre mudo (SIGPIPE em C/bash; `BrokenPipeError` +
   exit≠0 em Python). Os modelos abaixo trazem a proteção de cada linguagem — trap
   `PIPE` no bash, `except BrokenPipeError` + `os._exit(0)` no python, `SIG_IGN` no C++
   (a escrita falha e a próxima leitura cai no EOF da regra 5). O driver moderno já
   converte árbitro morto de SIGPIPE em RTE/WA, mas com a proteção o aluno recebe o
   MOTIVO ("encerrou sem ler a resposta").
6. **Não trate time limit**: o juiz mata todo mundo no TL (o driver recebe TERM e o
   veredicto sai TLE pelo tempo medido).

### Como vira veredicto (driver + compare genérico)

| o árbitro produziu | veredicto |
|---|---|
| score/info (última linha) | **Accepted** (o compare ecoa `SCORE=<valor>` p/ o summary) |
| `WRONG <motivo>` | **Wrong Answer** |
| nada + jogador morreu | **Runtime Error** |
| nada + jogador ok | **UE** (anormal — árbitro com bug) |
| (árbitro morto por **SIGPIPE** — o jogador fechou o pipe) | **RTE** (jogador morto) ou **WA** "encerrou sem ler" (saiu 0); resultado `WRONG` do árbitro, se houver, MANDA |
| (árbitro morto por outro sinal, ou exit ≠ 0 sem resultado `WRONG`) | **UE** — e linha de log NUNCA vira resultado (seria AC falso) |

## Exemplo completo: "adivinha o número"

O teste (`tests/input/1`) tem `alvo max_tentativas` (ex.: `42 10`). O árbitro informa o
número de tentativas; a cada palpite responde `MAIOR`, `MENOR` ou `OK`; o score é quantas
tentativas sobraram.

### Árbitro em bash (`arbitro.sh`)

```bash
#!/bin/bash
# jogador fechou o pipe (morreu/saiu sem ler a resposta)? SIGPIPE -> WRONG com motivo
trap 'echo "WRONG o programa encerrou sem ler a resposta" >&2; exit 0' PIPE
read -r ALVO MAX < "$1"                 # o teste vem de argv[1]
echo "$MAX"                             # stdout -> jogador
for ((i=1; i<=MAX; i++)); do
  read -r palpite || { echo "WRONG jogador encerrou sem acertar" >&2; exit 0; }
  echo "palpite $i: $palpite" >&2       # log livre
  if (( palpite == ALVO )); then
    echo OK
    echo "$((MAX - i + 1))" >&2         # ÚLTIMA linha do stderr = SCORE
    exit 0
  fi
  (( palpite < ALVO )) && echo MAIOR || echo MENOR
done
echo "WRONG estourou as $MAX tentativas" >&2
```

### Árbitro em python (`arbitro.py`)

```python
import os, sys

def jogo():
    alvo, maxt = map(int, open(sys.argv[1]).read().split())
    print(maxt, flush=True)
    for i in range(1, maxt + 1):
        try:
            p = int(input())
        except EOFError:
            print("WRONG jogador encerrou sem acertar", file=sys.stderr); return
        print(f"palpite {i}: {p}", file=sys.stderr)
        if p == alvo:
            print("OK", flush=True)
            print(maxt - i + 1, file=sys.stderr)   # última linha = score
            return
        print("MAIOR" if p < alvo else "MENOR", flush=True)
    print(f"WRONG estourou as {maxt} tentativas", file=sys.stderr)

try:
    jogo()
except BrokenPipeError:
    # jogador fechou o pipe (morreu/saiu sem ler a resposta)
    print("WRONG o programa encerrou sem ler a resposta", file=sys.stderr)
    sys.stderr.flush()
    os._exit(0)   # sem os._exit, o flush do stdout QUEBRADO na saída viraria exit != 0
```

### Árbitro em C++ (`arbitro.cpp` — compilado pelo driver, com cache)

```cpp
#include <cstdio>
#include <csignal>
int main(int argc, char** argv) {
    // jogador fechou o pipe? a escrita falha (em vez de SIGPIPE matar o árbitro) e a
    // PRÓXIMA leitura cai no EOF -> "WRONG jogador encerrou" (regra 5)
    std::signal(SIGPIPE, SIG_IGN);
    long alvo, maxt;
    FILE* f = fopen(argv[1], "r");
    if (!f || fscanf(f, "%ld %ld", &alvo, &maxt) != 2) {
        // GABARITO inválido é erro do PROBLEMA, não do aluno: logue e saia SEM
        // resultado (vira UE, visível p/ o setter) — nunca WRONG (viraria WA injusto)
        fprintf(stderr, "arbitro: teste invalido em %s\n", argv[1]);
        return 0;
    }
    printf("%ld\n", maxt); fflush(stdout);
    for (long i = 1, p; i <= maxt; i++) {
        if (scanf("%ld", &p) != 1) { fprintf(stderr, "WRONG jogador encerrou\n"); return 0; }
        if (p == alvo) {
            puts("OK"); fflush(stdout);
            fprintf(stderr, "%ld\n", maxt - i + 1);   // última linha = score
            return 0;
        }
        puts(p < alvo ? "MAIOR" : "MENOR"); fflush(stdout);
    }
    fprintf(stderr, "WRONG estourou as tentativas\n");
    return 0;
}
```

## Passo a passo no MOJ

```bash
# 1. monte o pacote normal (enunciado, tests/input com os cenários, tests/output
#    como PLACEHOLDER em par — pode ser "ok"), sols/good, sols/wrong

# 2. instale o árbitro + driver comum:
bash mojtools/interactive/install-interactive.sh <pacote> arbitro.cpp          # clássico
bash mojtools/interactive/install-interactive.sh <pacote> arbitro.py --score   # RANKING
#    -> scripts/arbitro.*, scripts/c/{prep,run}.sh + symlinks p/ TODAS as linguagens,
#       scripts/compare.sh (e scripts/summary.sh com --score); roda um smoke do árbitro

# 3. conf recomendado (o instalador avisa se faltar):
#    ULIMITS[-u]=10000              # interativo roda 2+ processos
#    TLMOD[calibrafactor]="10+1.5"  # o tempo do ÁRBITRO entra no TL: calibre com folga
#    CALIBRATIONTL=5                # TL usado na calibração antes de existir tl
#    ALLOWPARALLELTEST=n            # (recomendado) sem contenção entre árbitros
#    STOPWHEN_WA=y                  # (rank) para no primeiro WRONG

# 2b. atalho equivalente pela CLI (localiza o mojtools sozinho; MOJTOOLS_DIR aponta):
moj interactive <pacote> arbitro.cpp [--score]

# 4. teste com as suas soluções (num juiz real ou máquina com bwrap; no dev a jaula é fake):
bash mojtools/build-and-test.sh py <pacote>/sols/good/sol.py <pacote> y
moj test <pacote> --run          # equivalente pela CLI (todas as good)

# 5. transporte: 'moj push' agora CARREGA scripts/ (round-trip completo — symlinks do driver
#    incluídos); 'moj upload <id> <pacote>' (aceita o DIRETÓRIO) segue valendo p/ o tar inteiro:
moj push <pacote>
```

## Ranking (score contínuo)

Com `--score`, o `scripts/summary.sh` soma o `SCORE` de cada teste aceito e o veredicto
final vira `Accepted, Score <soma>, AAA… (N/T)`; **qualquer WRONG zera tudo**. O score de
cada teste é a última linha do stderr do árbitro (precisa ser numérico; info não-numérica
conta 0). Para score RELATIVO a uma referência (ex.: razão contra o custo ótimo), grave a
referência em `tests/output/N` e substitua o `scripts/compare.sh` por um custom que
calcule `SCORE=<referência>/<obtido>` — o resto do driver continua igual (é o padrão do
`fcte-delivery`).

## O jogador: linguagens e o FLUSH obrigatório

O driver despacha o jogador pela extensão do artefato compilado (`BIN`):

| Linguagem | como o driver invoca | flush no jogador |
|---|---|---|
| C, C++, Rust, Go, Pascal… (ELF) | `/tmp/dir/$BIN` | `fflush(stdout)` / `cout << flush` / `io::stdout().flush()` — **o `-static` do C ignora o `stdbuf`** |
| Python (`py`) | `python3 /tmp/dir/$BIN` | `print(..., flush=True)` |
| Bash (`sh`) | `bash /tmp/dir/$BIN` | `echo` já é por linha |
| **Java** | `java -Xmx… -Xss… <Classe>` (a classe com `main`, eleita no compile) | **`System.out.flush()` a cada resposta** |
| **Kotlin** | `java -Xmx… -Xss… -jar prog.jar` (`kotlinc -include-runtime`) | **`System.out.flush()` a cada resposta** |
| JavaScript | `node /tmp/dir/$BIN` | melhor esforço |

Sem ramo no dispatch (julgariam NÃO-interativamente): `cs`, `apl`, `riscv`, `spim`, `pl` —
restrinja as linguagens do problema.

> **JVM não obedece o `stdbuf`.** Java e Kotlin têm I/O próprio; sem `flush()` explícito a
> resposta fica no buffer, o árbitro nunca a recebe e o veredicto vira TLE (ou WRONG por
> "jogador encerrou"). **Diga isso no enunciado** de todo problema interativo que aceite
> JVM. Modelos que funcionam (`interativos#adivinhe-o-numero` traz os dois em `sols/good/`):

```java
BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
int n = Integer.parseInt(in.readLine().trim());
System.out.println(palpite);
System.out.flush();                 // <<< a cada resposta
String r = in.readLine();           // uma linha por vez (nunca "leia tudo até EOF")
```

```kotlin
val n = readLine()!!.trim().toInt()
println(palpite)
System.out.flush()                  // <<< a cada resposta
val r = readLine()?.trim() ?: return
```

Ler **uma linha por vez** também é obrigatório (a armadilha do `read_to_string` do Rust vale
para qualquer linguagem: o árbitro só fala depois de cada jogada, então ler até EOF trava).

## Erros comuns

- **Esquecer o flush** no árbitro ou no jogador ⇒ deadlock ⇒ TLE. O driver usa
  `stdbuf -oL`, mas isso não salva `printf` sem `\n`/flush — e **não alcança a JVM nem
  binário `-static`** (o `stdbuf` age por `LD_PRELOAD` sobre o stdio da libc). Ver a seção
  de flush por linguagem abaixo: em Java/Kotlin o flush explícito é OBRIGATÓRIO.
- **Árbitro saindo com exit ≠ 0** ou morrendo por sinal ⇒ UE (erro do problema, não WA) — exceto SIGPIPE, que o driver converte em RTE/WA (jogador fechou o pipe); resultado `WRONG` explícito é honrado mesmo com exit ≠ 0. **Árbitro SEM a proteção da regra 5½** ⇒ o aluno que morre no meio ganha veredicto sem motivo (RTE) em vez do WA explicativo.
- **`tests/output` faltando**: o portão de validação exige input/output em PARES —
  crie placeholders.
- **Linguagem sem o driver** julga NÃO-interativamente (o jogador leria `/tmp/in` cru) —
  o instalador cobre todas por default; se usar `--langs`, restrinja as linguagens do
  problema (`problem-langs`) às mesmas.
- **TL apertado**: o tempo do árbitro entra na medição — `TLMOD[calibrafactor]` generoso
  (os problemas reais usam de `"10+1.5"` a `"20+1"`).
- **Testar score parcial via checker**: não existe — parcial por teste é binário; rank é
  o `summary.sh`, e pontuação por grupos é `tests/score` (não misture os dois).
- **CLI antiga** (push que ignora `scripts/`): o `moj push` atual faz round-trip completo de
  `scripts/` (com os symlinks do driver); atualize a CLI ou use `moj upload <id> <dir>`.
