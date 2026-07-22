# Submissão de função: o aluno entrega só a função

Neste tipo de problema o aluno **não escreve programa**: ele entrega **uma função** (ou um
método, em Java) com a assinatura pedida no enunciado. Quem tem o `main` é **você** — o
*driver* do autor lê a entrada, chama a função do aluno e imprime o resultado. É o formato
ideal para exercitar um conceito isolado (uma struct, uma recursão, um cálculo) sem o aluno
se preocupar com I/O — e também o formato onde mais coisas dão errado em silêncio, então
leia a seção de boas práticas.

## Como funciona por baixo

O mecanismo é o `scripts/<lang>/compile.sh` do pacote (correção especial de compilação —
ver `correcao-especial.md`): ele **sobrepõe** a compilação padrão da linguagem e deve
terminar ecoando `BIN=<executável>`. O driver do autor **não é um arquivo do pacote**: ele
vive *inline* no `compile.sh` (heredoc) e é materializado na jaula na hora de compilar,
junto com o arquivo do aluno:

| Linguagem | Junção driver+aluno |
|---|---|
| C / C++ | driver vira `__judge_main.c(pp)`; o Makefile compila `$(wildcard *.c)` — os dois objetos linkam juntos |
| Python | o arquivo do aluno é **concatenado** com o rabo do driver em `__judge_run.py` (mesmo namespace) |
| Rust | `__judge_run.rs` faz `include!("<aluno>.rs")` e define o `main` |
| Java | o aluno envia `public class Main` com o **método estático**; o driver é a classe `Judge` (com o `main`) que chama `Main.suaFuncao(...)` |

O aluno digita a função no editor ou envia o arquivo — para ele, é uma submissão comum.

## Começando em 30 segundos

```sh
moj fn ./meu-problema                      # instala os 5 drivers-template (c cpp py java rs)
moj fn ./meu-problema --langs c,py        # ou só as linguagens que você vai liberar
```

No **editor web**, o mesmo template está na sub-aba **⚙ correção** (Soluções & Correção →
seletor de templates → "Submissão de função"). Os drivers instalados são um exemplo
**funcional** (`int soma(int a, int b)`) — edite as zonas `EDIT-ME` (protótipo, leitura,
chamada) e mantenha o resto.

Depois:

1. `sols/good/` recebe **só a função** (sem main), uma por linguagem liberada;
2. todo `tests/input/*` termina com a linha da **sentinela** `424242` (abaixo);
3. restrinja **`languages`** do problema às linguagens COM driver;
4. `moj push` + `moj validate`/`calibrate` como sempre (mexer em `scripts/` muda o
   tl-checksum ⇒ o Painel pede recalibração — correto, aceite).

## Compõe com checker (e o que NÃO compõe)

Submissão de função ocupa só o slot **COMPILE** (`scripts/<lang>/compile.sh`) — ela **compõe**
com um checker especial (slot COMPARE): `moj fn <dir> && moj checker <dir> checker.cpp` é
combinação normal (função cujo retorno tem várias formas válidas, tolerância de float…). Cada
installer preenche o próprio slot e preserva o resto. O que NÃO compõe é o **interativo**
(dono da execução por linguagem). A mecânica completa dos 4 slots: `correcao-especial.md`.

## Boas práticas anti-IO: a SENTINELA

**O risco nº 1 deste formato**: o aluno, em vez de usar os parâmetros, lê a entrada por
conta própria (`scanf`/`input()`/`Scanner` dentro da função) — e passa nos testes por
acidente, ou pior, quebra de formas confusas. A defesa canônica é barata e determinística:

1. **A entrada de todo teste termina com uma linha-mágica** (os templates usam `424242`).
   Ela é um *placeholder* que a função do aluno não conhece.
2. **O driver processa os casos e, no fim, LÊ a sentinela.** Se a função consumiu tokens da
   entrada, a leitura dessincroniza: a sentinela não bate (ou acabou a entrada) e o driver
   imprime `SENTINELA-VIOLADA (a funcao consumiu a entrada?)` — que **nunca** está na saída
   esperada ⇒ **Wrong Answer determinístico**, com o motivo visível no diff do relatório.
3. **Múltiplos casos por teste ajudam**: com N casos no mesmo arquivo, uma função que lê um
   token desloca TODOS os casos seguintes — o estrago aparece já no meio da saída.

Detalhes por linguagem:

- **C/C++/Java** leem em fluxo (scanf/Scanner): a dessincronização é literal — é o cenário
  clássico da sentinela.
- **Python/Rust**: o driver dos templates lê a **stdin inteira de uma vez** antes de chamar
  a função. Uma função que chame `input()` recebe EOF (EOFError ⇒ Runtime Error — também é
  detecção!). A checagem da sentinela continua valendo como validação da estrutura da
  entrada (e pega teste malformado do próprio autor).
- **Quando a função DEVE ler a entrada** (formato válido: "leia o resto do stdin e
  processe"), o driver precisa entregar o fluxo **posicionado**: leia os parâmetros
  byte-a-byte, sem buffering guloso (em Java, NADA de `Scanner` — ele engole blocos; ver o
  `apc/telescopio_funcao`, que lê com `read()` manual exatamente por isso). Nesse formato a
  sentinela não se aplica — quem valida é a saída.

## Banir funções (quando o exercício é "implemente na mão")

Os templates trazem um esqueleto comentado de **ban por grep** no fonte do aluno (padrão do
acervo: `apc/seno`, `apc/fatorial`, template `ban-funcoes-c`):

```sh
BANNED='cos|sin|tan'
grep -qE "(^|[^[:alnum:]_])($BANNED)[[:space:]]*\(" "$STU" && { echo "proibida" >&2; exit 1; }
```

Seja honesto com as limitações: grep **não** distingue comentário, alias, macro, `using`,
nem formas-método (`x.sin()`), e um aluno determinado contorna. Duas regras tornam o ban
efetivo na prática:

- **Restrinja `languages`** do problema às linguagens com driver+ban — sem isso, trocar de
  linguagem no envio **burla o esquema inteiro** (é o furo clássico).
- O ban é dissuasão didática, não sandbox: para bloqueio real de símbolo em C, o caminho
  futuro é inspecionar o objeto compilado (`nm`), que hoje **não** está implementado no
  acervo — não prometa mais do que o grep entrega.

## Erros comuns (colecionados do acervo)

- **Esquecer o `chmod +x`** em `scripts/*/compile.sh` ⇒ a jaula não executa ⇒ *Compilation
  Error em tudo*. (`moj fn` e o template do editor já instalam com +x; o validate confere.)
- **Java**: a classe do aluno chama-se **exatamente `Main`**, o método é **estático**, e o
  driver imprime float com `String.format(Locale.US, "%.6f", x)` — sem `Locale.US` a vírgula
  decimal pt-BR quebra a comparação.
- **Python**: qualquer código top-level do aluno **executa** na concatenação (inclusive
  `if __name__ == '__main__':` — o módulo É `__main__`). O enunciado deve pedir SÓ a função;
  um `print` solto do aluno vira WA (o que, convenhamos, é o comportamento certo).
- **Aluno enviando main junto**: em C/C++ o link falha (`duplicate main`) e vira CE — ok.
  Não "conserte" isso removendo o main do aluno no compile.sh: CE é o feedback certo.
- **Heredoc**: use `<<'EOF'` (quotado) para corpo literal em C/C++/Java; Python/Rust dos
  templates usam `<<EOF` **de propósito** (interpolam `$STU`) — não troque um pelo outro.
- **Float divergindo entre linguagens**: fixe a formatação (6 casas em todas) e, se precisar
  de tolerância, use o template `compare-float` (um `scripts/compare.sh` com ε).
- **Enunciado**: `## Entrada` descreve **os parâmetros** e `## Saída` **o retorno** — sem
  spoiler do driver (convenção adotada no acervo apc).
- **A mesma função em todas as linguagens liberadas** (mesmo nome; Rust tolera camelCase
  via `#![allow(non_snake_case)]`), mudando só os tipos.

## Referências no acervo

`apc/funcao_basica*` (o mais simples, 5 linguagens) · `apc/radares` (5 linguagens, mesmo
problema) · `apc/struct-ponto*` (sentinela/placeholder com contagem pós-chamada) ·
`apc/telescopio_funcao` (função que legitimamente lê o resto da entrada) · `apc/seno`,
`apc/fatorial` (ban por grep) · `monitores/abb-insere` (variação: teste hardcoded no driver,
sem stdin).
