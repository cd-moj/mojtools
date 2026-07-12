# `checkers/` — apoio compartilhado para corretores testlib

## `testlib.h`

Cabeçalho do [testlib](https://github.com/MikeMirzayanov/testlib/) (o de sempre nos pacotes
estilo *polygon*/Maratona), **compartilhado**: o pacote do problema carrega só o seu
`scripts/checker.cpp`, não uma cópia de 190 KB do cabeçalho.

O `build-and-test.sh` **exporta `MOJTOOLS_DIR`** (o `scripts/compare.sh` do pacote é
*executado*, não *sourced*, então não herda as variáveis dele). Um comparador testlib acha o
cabeçalho nesta ordem:

1. `$MOJTOOLS_DIR/checkers/testlib.h`
2. `$PWD/checkers/testlib.h` (o `build-and-test.sh` faz `cd $(dirname $0)`, então o CWD é o
   mojtools)
3. `<pacote>/scripts/testlib.h` (fallback: pacote antigo, ou uso fora do juiz)

## Compilar um checker: `-DBOCA_SUPPORT` e o contrato de saída

O juiz chama o comparador como `compare.sh <saída_do_time> <esperada> <entrada>` e lê o código
de saída: **4 = AC, 5 = AC/PE, 6 = WA** (convenção BOCA). Compilado com `-DBOCA_SUPPORT`, o
testlib já recebe os argumentos nessa ordem e já devolve 4/5/6.

**Cuidado com o PE.** No BOCA, *presentation error* é rejeição; no MOJ, **exit 5 vale
`AC,PE`, ou seja, ACEITO**. O testlib devolve PE em dois caminhos:

- `quitf(_pe, ...)` explícito do checker (ex.: "esperava SIM ou NAO, achei LIXO");
- saída truncada (`_unexpected_eof`) quando `ENABLE_UNEXPECTED_EOF` não está definido.

Sem tratamento, **uma saída lixo ou truncada é ACEITA**. Por isso o `compare.sh` dos pacotes
migrados mapeia **exit 5 → 6 (WA)**, cobrindo os dois caminhos. (Nos pacotes da IX Maratona do
IFB e da V Escola de Inverno havia 5 problemas cujos autores já tinham patchado o
`testlib.h` na mão para o segundo caso — o mapeamento no wrapper resolve de forma uniforme e
sem manter um testlib divergente.)
