# mojtools/testlib — checkers testlib normalizados no MOJ

Suporte de PRIMEIRA CLASSE a corretores especiais escritos com a
[testlib](https://github.com/MikeMirzayanov/testlib) (padrão Codeforces/Polygon).
**Guia de autoria (comece por aqui): [`docs/checker-testlib.md`](../docs/checker-testlib.md).**

## O que tem aqui

| arquivo | papel |
|---|---|
| `testlib.h` | testlib **vendorada** (v0.9.40-SNAPSHOT, md5 `c561daa4384f4bf8cb7ad9e0ff9adda8` — a cópia upstream, sem edição MOJ). O checker do pacote compila contra ELA; o pacote não carrega a sua. (`../checkers/testlib.h` é symlink p/ cá — compat com pacotes antigos.) |
| `checker-bridge.sh` | **a bridge, e ela mora AQUI** (fonte única): compila o `scripts/checker.cpp` do pacote no juiz sob demanda (cache fora de `scripts/`) e mapeia a interface testlib PADRÃO → contrato do MOJ. |
| `compare-stub.sh` | o que o PACOTE carrega como `scripts/compare.sh`: 10 linhas que chamam a bridge (`--pkg <dir do pacote>`). |
| `install-checker.sh` | instala fonte+stub num pacote (`install-checker.sh <pkg> <checker.cpp>`) e roda um smoke (gabarito×gabarito ⇒ Accepted). |

## Por que o pacote leva um STUB (e não a bridge)

Até 2026-07 cada pacote carregava **a sua cópia** da bridge. Quando se descobriu que o
fallback de compilação (o `g++` da rootfs via `bwrap` — o **único** caminho num juiz, que não
tem compilador no host) bindava o pacote no **caminho absoluto do host dentro de uma rootfs
read-only**, o `bwrap` morria com

```
bwrap: Can't mkdir parents for /…/pkg: Read-only file system
```

⇒ o checker não compilava ⇒ **UE em TODO teste de TODA solução**. E o conserto na bridge
**não alcançava nenhum dos 198 pacotes já empacotados**. Daí a regra:

> **driver canônico que roda no HOST ⇒ o pacote leva um STUB** (aponta p/ o mojtools);
> **o que entra na JAULA (`<lang>/run.sh`, `compile.sh`) ⇒ cópia real** (a jaula não enxerga
> o mojtools).

O `build-and-test.sh` **exporta `MOJTOOLS_DIR`** (o `compare.sh` é *executado*, não *sourced*);
é por ele que o stub acha a bridge. Pacote antigo com a bridge embutida **continua
funcionando** (sem `--pkg`, ela deriva o pacote do próprio caminho).

## O contrato (tudo num lugar só: a bridge)

O checker é **testlib padrão, SEM `-DBOCA_SUPPORT`** — copy-paste de um checker do
Polygon funciona. A bridge faz a ponte dos dois lados:

```
MOJ chama:     compare.sh <team_output> <answer> <input>
bridge chama:  checker    <input> <team_output> <answer>      (ordem padrão testlib)

testlib            exit  →  MOJ exit  →  veredicto
_ok                  0   →     4      →  Accepted
_wa                  1   →     6      →  Wrong Answer
_pe / _dirt         2/4  →     6      →  Wrong Answer
eof inesperado       8   →     6      →  Wrong Answer
_fail                3   →     7      →  UE (erro de juiz — gabarito/checker inválido)
_points              7   →     7      →  UE (parcial por checker NÃO suportado — use tests/score)
```

**Semântica do `_pe` (não confundir):** o "presentation error" da testlib significa
*saída fora do formato esperado / não parseável* — é resposta **errada** ⇒ **Wrong
Answer, sempre**. Não tem relação com o `AC,PE` do MOJ/BOCA (exit 5, "resposta certa,
só o espaçamento difere"), que continua existindo apenas no comparador **diff default**
(`lang/compare.sh`); a bridge nunca emite 5.

A mensagem do checker (stderr) aparece no log `.compare` do `report.html`.

## Onde compila e onde cacheia

- O compare roda **FORA da jaula, no host do juiz**. Compila com o **`g++` do host** se
  houver; senão — **o caso normal num juiz**, que só tem compilador na rootfs — com o **`g++`
  do `CAGE_ROOT` via `bwrap`, estático** (o binário roda no host). Os dois caminhos são dep
  DURA no `check-deps.sh`: sem nenhum, todo problema com checker daria UE.
  **No `bwrap`, tudo entra sob `/tmp`** (o `--tmpfs`) — a rootfs é `/` READ-ONLY, e bindar um
  caminho do host lá dentro faz o `bwrap` tentar criar o mountpoint na raiz RO. Mesmo padrão
  do `cage-run.sh`.
- O binário fica em **`<pkg>/.checker-cache/checker.<hash>`** — FORA de `scripts/`, de
  propósito: o `tl-checksum.sh` cobre `scripts/*`, e um binário lá dentro divergiria o
  checksum do juiz do do servidor. O hash cobre fonte+testlib+**compilador que vai compilar**
  (host ou rootfs): mudou o `checker.cpp` ⇒ recompila (e o tl-checksum muda via
  `scripts/checker.cpp` ⇒ recalibra). A compilação é protegida por `flock` (o juiz tem vários
  slots: sem trava, um slot apagava o binário que o outro acabara de gravar).
- Compila com `-include cassert -include cstring -include cstdint`: o `<bits/stdc++.h>` do
  **gcc ≥ 15** não puxa mais esses cabeçalhos transitivamente e muitos checkers do Polygon
  usam `assert()`/`memset()` sem incluir — sem isso, não compilam ⇒ UE em todo teste.
- Falha de compilação/checker ⇒ `exit 7` = **UE** (erro visível), nunca WA silencioso.

## Por que “sem BOCA” (histórico do patch)

Os pacotes legados (365 ELFs em `moj-problems-backup`!) compilavam o checker com
`-DBOCA_SUPPORT` (args na ordem do MOJ + exits 4/5/6/7) e commitavam o **binário estático
de ~2.7MB como `scripts/compare.sh`**, cada um com sua cópia de `testlib.h` — que divergiu
em 3 variantes de 1 linha (o “patch de código de retorno”):

| família | edição | efeito |
|---|---|---|
| eimp (gama/alazão…) | nenhuma (upstream) | `_pe` ⇒ exit 5 ⇒ Accepted,PE |
| saad | `PE_EXIT_CODE 5→6` | `_pe` ⇒ WA |
| estrutural | eof inesperado `PE→WA` | eof ⇒ WA |

A edição da família saad (`_pe`⇒WA) era a **semântica correta** — o upstream com BOCA
mapeia `_pe` p/ o exit 5 do BOCA (aceito), misturando dois conceitos diferentes de "PE".
Com a bridge, o acoplamento MOJ↔testlib vive num único script versionado, `_pe`/eof são
fixados em WA p/ todos, e o pacote carrega só o fonte.
