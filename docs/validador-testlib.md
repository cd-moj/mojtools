# Validador de entrada (testlib) — guia de autoria

Um **validador de entrada** confere se cada teste de `tests/input` segue o formato e os limites que o
enunciado promete. Ele usa a [testlib](https://github.com/MikeMirzayanov/testlib) no modo
`registerValidation`, o padrão do Polygon. Um validador de Polygon funciona copiado e colado.

Por que ter um: se um teste viola o enunciado, a "saída esperada" pode estar errada, e ninguém percebe.
Caso real: um teste tinha `n = 1296` num problema de `N <= 1000`. A solução de referência tinha um vetor
de 1001 posições, e a saída esperada daquele teste era lixo de memória.

O validador **não julga solução nenhuma**. Ele só confere as entradas.

## Onde ele fica

`scripts/validator.cpp`, no pacote. Nada mais: o `testlib.h` vem do mojtools (um `scripts/testlib.h` no
pacote, se existir, tem precedência — o mesmo do checker).

- O arquivo viaja com o pacote: editor web (aba Soluções & Correção › ⚙ correção), `moj push`/`clone`,
  `moj upload`.
- Mexer no validador **não** pede recalibração do tempo-limite e **não** esconde o TL da prova (ele fica
  fora do `tl_checksum`). Ele entra na versão do pacote, então o juiz baixa o validador novo.

## Um validador

```cpp
#include "testlib.h"

int main(int argc, char* argv[]) {
    registerValidation(argc, argv);
    int n = inf.readInt(1, 1000, "N");          // 1 <= N <= 1000; o nome aparece na mensagem
    inf.readEoln();
    for (int i = 0; i < n; i++) {
        if (i > 0) inf.readSpace();              // exatamente UM espaço entre os números
        inf.readLong(-1000000000LL, 1000000000LL, "a_i");
    }
    inf.readEoln();                              // a última linha termina com \n
    inf.readEof();                               // e não sobra nada depois dela
}
```

Regras:

- Leia **tudo** com `inf.read…`, com os limites do enunciado. Um `readInt()` sem limites só confere
  que é um número.
- Termine com `inf.readEoln()` e `inf.readEof()`. Sem o `readEof()`, lixo no fim do arquivo passa.
- A testlib é estrita com espaço: `readSpace()` é UM espaço, `readEoln()` é UMA quebra de linha. Um
  teste sem `\n` no fim falha em `Expected EOLN`. Isso é intencional: é o formato que o enunciado
  promete ao aluno.
- Restrições entre valores (ex.: "o grafo é conexo", "a soma dos N não passa de 10^6") entram como
  código normal, com `ensuref(condição, "mensagem", …)`.

O editor web tem o template **"Validador de entrada (testlib)"** com este exemplo.

## Rodar na sua máquina

```bash
moj validator . validator.cpp     # instala em scripts/validator.cpp e roda sobre tests/input/*
moj validator                     # (dentro da pasta do problema) roda o que o pacote já tem
```

Ele compila com o seu `g++` e usa o **mesmo** script que o juiz usa
(`mojtools/testlib/validator-run.sh`), então o resultado local é o que o juiz vai mostrar. Sai 0 quando
todas as entradas passam e 1 quando alguma é inválida. Exige o checkout do mojtools, como o
`moj checker`.

## No juiz

A **calibração completa** (botão Calibrar, `moj calibrate`, Validar e publicar) roda o validador antes das
soluções. A calibração rápida da 1ª submissão não roda (ela não pode atrasar o julgamento).

O resultado aparece:

- no editor, aba Publicação & Pacote › Validação & calibração, no cartão de cada juiz (linha
  **Entradas**, com a mensagem da testlib de cada entrada reprovada), e no item **Entradas** da barra
  de prontidão;
- no Painel (coluna Soluções) e no `moj check`/`moj calib`;
- como pendência: entrada inválida (`inputs_invalid:<n>`) ou validador que não rodou (`inputs_error`)
  deixa o problema **não pronto**. Pacote sem validador não é pendência.

| Resultado | Quando |
|---|---|
| todas passaram | o validador saiu com 0 em todas as entradas |
| *n* inválidas | a testlib reprovou *n* entradas (código `_fail` = 3); a mensagem diz onde e por quê |
| não rodou | não compilou, passou de 5 s numa entrada, ou passou do orçamento de 60 s (compilação incluída) |

## Detalhes técnicos

- `testlib/validator-run.sh <pkg>` imprime uma linha JSON no formato de uma entrada do
  `.calib-sols.json` (`category: "validator"`, `verdict: none|ok|invalid|error`,
  `tests: [{name, code: OK|INVALID|FAIL, msg}]`). O calibreitor a anexa ao vetor das soluções, o agente
  do juiz a sobe no `/judge/calib-report` com o resto, e o servidor a separa
  (`cdmoj/server/api/v1/lib/calib-expect.sh`).
- Compila como o checker (`testlib/checker-bridge.sh`): `g++` do host ou, sem ele, o `g++` da rootfs em
  `bwrap`, estático. Cache em `<pkg>/.validator-cache/` (fora de `scripts/`, fora do git).
- Roda no HOST do juiz, como o checker e o `compare.sh`, com timeout de 5 s por entrada
  (`VALIDATOR_TL`), 4 GB de endereço e orçamento total de 60 s (`VALIDATOR_BUDGET`).
- `validate-problem.sh` avisa (sem reprovar) quando `scripts/validator.cpp` não chama
  `registerValidation`.
