# `checkers/` — COMPAT (o canônico mora em `testlib/`)

Este diretório existe só para **não quebrar pacotes antigos**. O caminho oficial do checker
testlib é:

- **bridge**: `mojtools/testlib/checker-bridge.sh` (fonte única — o pacote leva só o
  `testlib/compare-stub.sh` como `scripts/compare.sh`);
- **cabeçalho**: `mojtools/testlib/testlib.h` (vendorado, uma cópia só).

`checkers/testlib.h` é um **symlink** para `../testlib/testlib.h`: pacotes migrados antes da
unificação carregam uma **cópia da bridge** dentro de `scripts/compare.sh` que procura o
cabeçalho em `$MOJTOOLS_DIR/checkers/testlib.h`. Eles continuam funcionando; pacote novo (ou
reinstalado com `install-checker.sh`) não passa mais por aqui.

## Por que a bridge saiu de dentro do pacote

Cada pacote carregava a **sua cópia** da bridge. Quando se descobriu que o fallback de
compilação (`g++` da rootfs via `bwrap`, o único caminho num juiz — que não tem compilador no
host) bindava o pacote no **caminho absoluto do host dentro de uma rootfs read-only**
(`bwrap: Can't mkdir parents … Read-only file system` ⇒ checker não compila ⇒ **UE em todo
teste**), o conserto no mojtools **não alcançou nenhum dos 198 pacotes já empacotados**. Daí a
regra:

> **driver canônico que roda no HOST ⇒ o pacote leva um STUB** (aponta p/ o mojtools);
> **o que entra na JAULA (`<lang>/run.sh`, `compile.sh`) ⇒ cópia real.**

## O contrato de saída (e a pegadinha do PE)

O juiz chama `compare.sh <saída_do_time> <esperada> <entrada>` e lê o código: **4 = AC,
5 = AC/PE, 6 = WA** (qualquer outro = erro de juiz). A bridge canônica compila o checker com
**testlib PADRÃO** (sem `-DBOCA_SUPPORT`) e traduz ela mesma: `_ok`⇒4; `_wa`/`_pe`/`_dirt`/
eof-inesperado⇒**6**; `_fail`/`_points`⇒erro de juiz.

O cuidado com o PE está embutido nessa tradução: o `_pe` do testlib é "saída fora do formato /
não parseável" (= **resposta errada**), enquanto o **exit 5** do MOJ significa "certa, só o
espaçamento difere" (= **aceito**). Mapear `_pe` para 5 faria **saída lixo ou truncada ser
ACEITA** — por isso ele vai para 6. (As cópias antigas, compiladas com `-DBOCA_SUPPORT`,
resolviam o mesmo problema convertendo `5 → 6` no fim do script.)
