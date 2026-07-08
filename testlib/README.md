# mojtools/testlib — checkers testlib normalizados no MOJ

Suporte de PRIMEIRA CLASSE a corretores especiais escritos com a
[testlib](https://github.com/MikeMirzayanov/testlib) (padrão Codeforces/Polygon).
**Guia de autoria (comece por aqui): [`docs/checker-testlib.md`](../docs/checker-testlib.md).**

## O que tem aqui

| arquivo | papel |
|---|---|
| `testlib.h` | testlib **vendorada** (v0.9.40-SNAPSHOT, md5 `c561daa4384f4bf8cb7ad9e0ff9adda8` — a cópia upstream usada pelos pacotes eimp2024, sem edição MOJ). O checker do pacote compila contra ELA; o pacote não precisa (nem deve) embutir a sua. |
| `checker-bridge.sh` | vai p/ o pacote como `scripts/compare.sh`: compila `scripts/checker.cpp` no juiz sob demanda (cache) e mapeia a interface testlib PADRÃO → contrato do MOJ. |
| `install-checker.sh` | instala checker+bridge num pacote (`install-checker.sh <pkg> <checker.cpp>`) e roda um smoke (gabarito×gabarito ⇒ Accepted). |

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

- O compare roda **FORA da jaula, no host do juiz** — o requisito real é **g++ no host**
  (presente no dev e nos juízes C3SL). Fallback: sem g++ no host mas com `CAGE_ROOT`,
  compila com o g++ do rootfs via `bwrap`, **estático** (o binário roda no host).
- O binário fica em **`<pkg>/.checker-cache/checker.<hash>`** — FORA de `scripts/`, de
  propósito: o `tl-checksum.sh` cobre `scripts/*`, e um binário lá dentro divergiria o
  checksum do juiz do do servidor. O hash cobre fonte+testlib+compilador: mudou o
  `checker.cpp` ⇒ recompila (e o tl-checksum muda via `scripts/checker.cpp` ⇒ recalibra).
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
