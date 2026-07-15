# mojtools

Ferramentas de **julgamento** e de **enunciado** do MOJ, o juiz online do CD
(`moj.naquadah.com.br`). Tudo aqui é bash.

O mojtools roda em **dois lugares diferentes**, e isso explica a divisão do repositório:

| Metade | Onde roda | O que faz |
|---|---|---|
| **Julgamento** | em cada **máquina de juiz** | compila e executa código de aluno dentro de um sandbox, compara a saída, decide o veredito, mede o tempo-limite |
| **Enunciado e validação** | no **servidor web** | renderiza o enunciado, confere se o pacote está completo, gera o índice que o aluno consome |

Uma máquina de juiz precisa de dois repositórios apenas: o `judge` (o agente) e este. Ela **não**
precisa do `cdmoj`.

> **O formato do pacote de problema está documentado em `cdmoj/docs/PACOTE.md`.** Aquele documento é
> a referência (o que é cada arquivo, o que são orgs e coleções, o que são os metadados). Este aqui é
> o manual das **ferramentas**: o roteiro de montagem e o que cada comando faz.

## Sumário

1. [Preparar a máquina](#1-preparar-a-máquina)
2. [Roteiro: montar um pacote do zero](#2-roteiro-montar-um-pacote-do-zero)
3. [Recursos opcionais](#3-recursos-opcionais)
4. [O caminho normal do autor: a CLI](#4-o-caminho-normal-do-autor-a-cli)
5. [Referência de comandos](#5-referência-de-comandos)
6. [As linguagens (`lang/`)](#6-as-linguagens-lang)
7. [Como um problema customiza o julgamento](#7-como-um-problema-customiza-o-julgamento)
8. [Mapa do repositório](#8-mapa-do-repositório)

---

## 1. Preparar a máquina

Para **renderizar e validar** enunciados basta ter `pandoc` e `jq`. Para **julgar** código de aluno
você precisa do sandbox (`bwrap`, do bubblewrap) e dos compiladores.

```sh
make deps            # confere o que falta na máquina (roda o check-deps.sh)
```

O `make deps` lista o que está faltando. Dependência **dura** faz o comando sair com erro;
dependência opcional (como `cset` ou `podman`) só vira aviso.

Os compiladores podem vir de dois lugares:

- **Da própria máquina** (o default). Simples, mas o toolchain é o que estiver instalado ali.
- **De um rootfs próprio**, um Ubuntu com todos os compiladores na versão certa. É o modo
  recomendado para um juiz de verdade, porque o toolchain fica igual em todas as máquinas:

```sh
make sysroot                       # constrói o rootfs (precisa de podman) e exporta p/ ~/moj-sysroot
export CAGE_ROOT=$HOME/moj-sysroot # a partir daqui, a jaula roda dentro do rootfs
```

Antes de usar a máquina numa prova de verdade, rode a bateria de estresse do sandbox:

```sh
bash stress-cage.sh
```

Ela tenta fork bomb, alocar memória sem parar, encher o disco, abrir rede e ler segredos do
`/etc`. Se **qualquer** caso falhar, não use aquela máquina em prova. Detalhes do sandbox, da
escolha da raiz e do endurecimento: **[SANDBOX.md](SANDBOX.md)**.

## 2. Roteiro: montar um pacote do zero

Vamos montar um problema chamado `soma`, que lê dois inteiros e imprime a soma. O roteiro é o
caminho manual, usando os scripts direto. É o que a CLI e o editor web fazem por baixo, e conhecê-lo
ajuda a entender o que deu errado quando algo dá errado.

### Passo 1: criar o esqueleto

```sh
mkdir -p soma/docs soma/tests/input soma/tests/output soma/sols/good
cd soma
```

### Passo 2: escrever o enunciado

O arquivo é `docs/enunciado.md`. **As seções `## Entrada` e `## Saída` são obrigatórias**: sem elas
a validação reprova o problema.

```sh
cat > docs/enunciado.md <<'EOF'
Dados dois números inteiros, calcule a soma dos dois.

## Entrada

A entrada contém dois inteiros $a$ e $b$ ($0 \le a, b \le 1000$), um em cada linha.

## Saída

Imprima um único inteiro, a soma de $a$ e $b$.
EOF
```

Repare em duas coisas que **não** estão no arquivo:

- **Não há título.** O título é um campo do metadado, não uma linha do texto. Se você escrever
  `% Soma` na primeira linha, o renderizador vai apagar (é um formato legado).
- **Não há exemplo.** Os exemplos são montados a partir dos arquivos de teste, no passo seguinte, e
  injetados no fim do enunciado. Se você escrever um exemplo à mão aqui, ele vai aparecer duas vezes.

### Passo 3: criar os exemplos

Exemplo é todo teste cujo nome **começa com `sample`**. Ele aparece no enunciado **e** corrige a
submissão, como qualquer outro teste.

```sh
printf '2\n3\n' > tests/input/sample1
printf '5\n'    > tests/output/sample1
```

O nome do arquivo de entrada e o do arquivo de saída têm que ser **iguais**. A validação confere isso
nos dois sentidos.

### Passo 4: criar os testes ocultos

Qualquer nome que não comece com `sample` é um teste oculto: corrige, mas o aluno não vê.

```sh
printf '0\n0\n'       > tests/input/test-001
printf '0\n'          > tests/output/test-001
printf '1000\n1000\n' > tests/input/test-002
printf '2000\n'       > tests/output/test-002
```

### Passo 5: escrever a solução de referência

Pelo menos **uma** solução correta em `sols/good/` é obrigatória. **A extensão do arquivo é o que
diz a linguagem.**

```sh
cat > sols/good/sol.c <<'EOF'
#include <stdio.h>
int main(void){ int a, b; scanf("%d %d", &a, &b); printf("%d\n", a + b); return 0; }
EOF
```

Ponha uma solução `good` **em cada linguagem que você quer liberar para o aluno**. O tempo-limite é
calibrado por linguagem, e linguagem sem solução `good` aceita não ganha tempo-limite, ou seja, o
aluno não consegue usá-la.

### Passo 6: escrever o `conf`

Os limites de execução. Para a maioria dos problemas os defaults servem, e o `conf` fica curto:

```sh
cat > conf <<'EOF'
TLMOD[calibrafactor]=1.35
ULIMITS[-u]=10000
ALLOWPARALLELTEST=y
EOF
```

O `calibrafactor` é a **folga**: o tempo-limite vai ser o tempo da sua solução `good` multiplicado por
1.35. O `ULIMITS[-u]` é o número de processos (Java e outras runtimes precisam de bem mais do que o
default de 1024). A lista completa das chaves está em `cdmoj/docs/PACOTE.md`.

Falta ainda o arquivo `author`, que é obrigatório:

```sh
echo 'Fulano de Tal' > author
printf '#implementacao\n#iniciante\n' > tags
```

### Passo 7: julgar localmente

Agora dá para rodar o julgamento na sua própria solução, para ver se o pacote funciona:

```sh
bash ../mojtools/build-and-test.sh c sols/good/sol.c . y
```

A saída tem duas linhas que importam:

- a **primeira** linha é o diretório de trabalho, onde ficaram os artefatos (inclusive o
  `report.html`, o mesmo relatório que o aluno vê);
- a **última** linha é o **veredito**, por exemplo `Accepted,100p`.

Se der `Compilation Error`, o compilador reclamou. Se der `Wrong Answer`, a saída não bateu. Abra o
`report.html` do diretório de trabalho: ele mostra, teste a teste, a entrada, o que era esperado, o
que saiu, o tempo e o pico de memória.

> Este passo precisa de um sandbox **de verdade**. Se na sua máquina o `bwrap` for o `fbwrap` (o
> no-op do firejail, comum em máquina de desenvolvimento), o julgamento local não roda. Isso não é
> defeito do pacote: mande o problema para o servidor e deixe a calibração num juiz de verdade fazer
> a conferência.

### Passo 8: validar (o portão de qualidade)

```sh
bash ../mojtools/validate-problem.sh . soma#soma
```

O comando sai com 0 se passou, e escreve um relatório em `run/validation/<id>.json` dizendo, item a
item, o que passou e o que não passou. Ele confere: autor, enunciado, as seções `## Entrada` e
`## Saída`, se o pandoc renderiza, se há exemplo, se todo teste está pareado, se há solução `good`,
e se a `good` é aceita.

**Todas** as checagens precisam passar. Se o comando reprovar, ele imprime no stderr a lista do que
falhou.

Se passar, ele já **indexa** o problema (chama o `gen-problem-json.sh` sozinho).

### Passo 9: calibrar (descobrir o tempo-limite)

```sh
bash ../mojtools/calibreitor.sh .
```

O calibrador roda cada solução de `sols/good/`, mede o pior tempo por linguagem, multiplica pelo
`calibrafactor` e grava o resultado em `tl.<nome-da-máquina>` (e uma cópia em `tl`). Depois roda as
soluções de `pass/`, `slow/` e `wrong/`, se existirem, para você conferir que o tempo-limite reprova
o que tem que reprovar.

**Sem o arquivo `tl` não é possível julgar submissão nenhuma**: o julgamento precisa saber o
tempo-limite. Num juiz de verdade isso é automático, o agente calibra o problema na primeira vez que
recebe uma submissão dele.

Você **não escreve** o tempo-limite à mão. Ele é medido.

### Passo 10: gerar o índice do aluno

```sh
bash ../mojtools/gen-problem-json.sh . soma#soma
```

Gera `contests/treino/var/jsons/soma#soma.json`, que é o que o frontend consome: o título, o autor, as
tags, as coleções, os tempos-limite, o enunciado já em HTML e os exemplos. É o passo final, e ele já
foi executado pelo passo 8 se a validação passou.

Pronto: o pacote está completo, validado, calibrado e indexado.

## 3. Recursos opcionais

Os três recursos abaixo são opcionais, e cada um já tem um guia próprio. Aqui vai só o suficiente para
você saber que existem e quando usar.

### Pontuação por grupos (subtarefas)

Por padrão a nota do problema é a **porcentagem de testes** que passaram. Se você quer **subtarefas**
(o estilo da OBI: um grupo de testes fáceis vale 40 pontos, o grupo geral vale 60), crie o arquivo
`tests/score`:

```
sample* - 0 pontos
soma_facil_* - 40 pontos
soma_geral_* - 60 pontos
```

Cada linha é um grupo: um ou mais globs de nome de teste, ` - `, e o peso. O grupo é **tudo ou nada**
(um teste falhou, o grupo vale 0), e o valor do problema é a **soma dos pesos**. Quem interpreta o
arquivo é o `score-summary.sh`, sozinho, sem você precisar chamar nada.

### Checker (quando há mais de uma resposta certa)

Se a resposta não é única (tolerância de ponto flutuante, várias ordens válidas, qualquer caminho
mínimo serve), a comparação exata não funciona. Você precisa de um **checker**, um programa que olha a
entrada, a resposta do aluno e o gabarito, e decide.

O jeito recomendado é escrever o checker em C++ com a [testlib](https://github.com/MikeMirzayanov/testlib)
(o padrão do Codeforces) e instalá-lo:

```sh
bash mojtools/testlib/install-checker.sh <pacote> checker.cpp
```

Isso põe o **fonte** em `scripts/checker.cpp` e um **stub** de 10 linhas em `scripts/compare.sh`,
que chama a bridge do mojtools (`testlib/checker-bridge.sh`) — é ela que compila o checker no juiz
sob demanda. O pacote **não** carrega a bridge nem o `testlib.h`. **Nunca commite o binário do
checker.**

Guia de autoria, com receitas prontas: **[docs/checker-testlib.md](docs/checker-testlib.md)**.

### Problema interativo

Quando a solução do aluno precisa **conversar** com um árbitro (fazer perguntas e receber respostas,
como num jogo de adivinhação), o problema é interativo:

```sh
bash mojtools/interactive/install-interactive.sh <pacote> arbitro.cpp [--score]
```

O árbitro recebe o teste como argumento e conversa com a solução por FIFOs. A **última linha** do
stderr do árbitro é o resultado (`WRONG <motivo>` reprova). Com `--score`, o problema vira um ranking
(a nota é o desempenho, não o acerto).

Guia de autoria: **[docs/problema-interativo.md](docs/problema-interativo.md)**.

### Outros ajustes de correção

Submissão de função (o aluno entrega só a função, não o programa), proibir uma função da biblioteca
para forçar a implementação na mão, comparador com tolerância de ponto flutuante: tudo isso é
`scripts/`, e está em **[docs/correcao-especial.md](docs/correcao-especial.md)**.

Há **templates prontos** em `script-templates/`, que o editor web oferece num seletor.

## 4. O caminho normal do autor: a CLI

Na prática, quem escreve problema não chama estes scripts na mão: usa a CLI `moj` (o repositório
`moj-cli`), que fala com a API do servidor. A CLI e o editor web fazem exatamente o que o roteiro da
seção 2 descreve.

```sh
moj login
moj new <org> soma            # cria o esqueleto do pacote
                              # (edita enunciado, testes, soluções)
moj test soma --run           # pré-voo local e julga, chamando o build-and-test.sh daqui
moj preview soma              # abre o enunciado renderizado, pelo render-statement.sh daqui
moj push soma                 # envia o pacote para o servidor
moj publish <org>#soma        # o servidor valida e calibra; se passar, o problema entra no treino
moj check <org>#soma          # acompanha: validação, tempo-limite por juiz, good sem TL
```

Para os recursos opcionais, a CLI tem atalhos que chamam os instaladores deste repositório:
`moj checker <dir> <checker.cpp>` e `moj interactive <dir> <arbitro>`.

Para a CLI achar o mojtools, tenha um checkout dele ao lado (`~/moj/mojtools`) ou aponte a variável
`MOJTOOLS_DIR`.

## 5. Referência de comandos

Os scripts abaixo estão todos na raiz do repositório. Salvo indicação em contrário, todos aceitam
caminho relativo e escrevem mensagens de erro no stderr.

### `build-and-test.sh`: julgar uma solução

O coração do juiz. Compila uma solução e a roda contra todos os testes do pacote, dentro do sandbox.

```
build-and-test.sh <linguagem> <arquivo-fonte> <pacote> [y|n]
```

O quarto argumento (`y`) manda rodar **todos** os testes mesmo depois de já ter dado erro (útil para
calibrar e para pontuação por grupos).

**A saída tem um contrato**, e os dois lados dela importam:

- a **primeira linha** do stdout é o **diretório de trabalho**, onde ficam todos os artefatos;
- a **última linha** do stdout é o **veredito**, com a nota embutida (`Accepted,100p`,
  `Wrong Answer,40p`).

Artefatos que ficam no diretório de trabalho (ele **não** é apagado; quem chamou é que recolhe):

| Arquivo | O que é |
|---|---|
| `report.html` | o relatório da submissão, autocontido. É o que o aluno vê |
| `report.env` | o veredito **estruturado**, para quem for consumir por programa (ver abaixo) |
| `compile.log.*` | o que o compilador disse |
| `<teste>-team_output`, `<teste>-log.*` | por teste: a saída do aluno, o tempo, o veredito |

O `report.env` é a fonte de verdade para o servidor. Ele traz `VERDICT_CANON` (o veredito **limpo**,
sem a nota: `Accepted`, `Wrong Answer`, `Time Limit Exceeded`, `Memory Limit Exceeded`,
`Runtime Error`, `Compilation Error`), `SCORE` e `SCORE_MAX`, `SCORE_KIND` (`tests` para porcentagem
de testes, `points` para soma de grupos), `SCORE_GROUPS` (os grupos, em JSON, na ordem do
`tests/score`) e `CORRECT`/`TOTALTESTS`.

Códigos de saída: `0` julgou (o veredito está na última linha), `1` erro de uso **ou Compilation
Error**, `3` a linguagem não está disponível, ou falta o arquivo `tl`, ou o pacote não tem testes.

Lê do ambiente: `CAGE_ROOT` (a raiz do sandbox), `CAGE_ROOT_<LANG>` (raiz diferente para uma
linguagem específica), `MOJ_PROBLEM_ID`.

Lê do `conf` do problema: todas as chaves de limite (ver `cdmoj/docs/PACOTE.md`).

### `cage-run.sh`: a jaula

O sandbox propriamente dito, feito com **bubblewrap** (`bwrap`). Roda **um** script isolado: sem
rede, sem acesso ao seu `$HOME`, com o sistema de arquivos só-leitura, como usuário sem privilégio, e
com limite de tempo e de memória.

Você normalmente **não chama este script à mão**: quem chama é o `build-and-test.sh`, uma vez para
compilar e uma vez por teste.

```
cage-run.sh -d <dir> -i <entrada> -o <saída> -s <log-stderr> -t <log-tempo> -r <script> -T <limite> -B <arq>
            [-w <dir-rw>] [-b <bind>]... [-R <rootfs>] [-M <MB>] [-S <cpus> -U <user>]
```

| Flag | O que faz |
|---|---|
| `-r` | o script a executar (precisa ter o bit de execução) |
| `-d` | diretório com os arquivos, entra na jaula como `/tmp/dir`, só-leitura |
| `-i` / `-o` | a entrada (`/tmp/in`, só-leitura) e a saída (`/tmp/out`, escrita) |
| `-w` | um diretório de escrita em `/tmp/rwdir`. É o modo usado na **compilação** |
| `-T` | tempo-limite duro (maior que o do problema, é uma rede de segurança) |
| `-M` | limite de memória, em MB |
| `-R` | a raiz do sistema de arquivos da jaula (o rootfs). Também vem da variável `CAGE_ROOT` |
| `-b` | um bind extra para dentro da jaula (usado pelos `prep.sh` das linguagens) |
| `-S` / `-U` | fixa CPU e usuário (só como root; os dois têm que vir juntos) |

O `/etc` entra inteiro na jaula, mas com **máscaras**: `shadow`, `sudoers`, chaves de `ssh` e afins
são zerados, e `passwd`/`group` viram arquivos sintéticos de uma linha. Detalhes em
**[SANDBOX.md](SANDBOX.md)**.

### `calibreitor.sh`: medir o tempo-limite

```
calibreitor.sh <pacote>
```

Roda cada solução de `sols/good/`, pega o pior tempo por linguagem, multiplica pelo
`TLMOD[calibrafactor]` (1.35 por padrão) e grava `tl.<máquina>` e `tl` dentro do pacote. Só emite
tempo-limite para linguagem que teve pelo menos uma solução `good` **aceita** naquela máquina.

Depois, roda as soluções de `pass/`, `slow/` e `wrong/` para conferência (o `CALIBRATE_ONLY_GOOD=1`
pula essa parte, e é o que o agente do juiz usa quando está com pressa).

Grava também um `report.html` por solução em `.calib-reports/`, que o agente sobe para o servidor.

**Concorrência (juiz multi-slot):** a tabela de TL de trabalho é PRIVADA — o calibreitor exporta
**`MOJ_TLFILE`** (um temp) para os `build-and-test.sh` filhos, e essa env **vence** a seleção
`tl.<máquina>`/`tl` (é o único jeito de apontar um TL fora do pacote). Os `tl.<máquina>`/`tl`
finais são publicados **atomicamente** (mktemp no mesmo diretório + `mv`) e o `.calib-reports/`
é montado em staging e trocado por rename no fim: outro slot julgando o MESMO problema nunca vê
placeholder, tabela parcial nem dir de reports pela metade. (Duas calibrações do mesmo pacote no
mesmo host continuam NÃO devendo rodar em paralelo — o agente serializa com flock por-problema;
rodando na mão, não dispare duas.)

### `validate-problem.sh`: o portão de qualidade

```
validate-problem.sh <pacote> [<id>]
```

Sai com 0 se o pacote passou, diferente de 0 se reprovou, e sempre escreve um relatório em
`$RUNDIR/validation/<id>.json` com o resultado de cada checagem. **Todas** as checagens são
obrigatórias: `has_author`, `has_statement`, `html_builds`, `secao_entrada`, `secao_saida`,
`examples_present`, `tests_paired`, `has_good_sol`, `good_sol_accepts`.

Alguns avisos são só informativos e **não** reprovam: LaTeX vazando na prosa do enunciado, exemplo
escrito à mão no texto, checker commitado como binário.

Se o pacote passa, o script chama o `gen-problem-json.sh` sozinho.

Sem um sandbox de verdade (isto é, quando o `bwrap` é o `fbwrap`), a checagem `good_sol_accepts` é
**adiada** para a calibração, que roda num juiz real. Não é bug.

Variáveis: `VALIDATE_RUN_SOLS=0` pula a execução das soluções; `RUNDIR` diz onde escrever o relatório.

### `gen-problem-json.sh`: gerar o índice do aluno

```
gen-problem-json.sh <pacote> [<id>]
```

Lê o pacote e escreve `contests/treino/var/jsons/<id>.json`, que é o que o frontend consome:

```json
{ "id": "...", "title": "...", "author": "...", "time_limits": {...}, "tags": [...],
  "collections": [...], "languages": [...], "statement_html_b64": "..." }
```

Os **exemplos** vêm sempre dos arquivos de teste (`tests/input/sample*`, na ordem), nunca do texto do
enunciado, e são injetados no HTML. As explicações de cada exemplo vêm de `docs/sample-notes.json`.
O editorial (`docs/solucao.md`) é **ignorado** de propósito: ele não pode chegar ao aluno.

Os tempos-limite vêm do store dos juízes (`run/tl/<id>.json`) e são o **máximo entre as máquinas**,
mas só valem se o checksum do pacote ainda bate. Se o pacote mudou e ninguém recalibrou, o campo sai
vazio.

Se o problema é privado, o JSON vai só para `jsons-private/`, e o do `jsons/` é removido.

### `render-statement.sh`: renderizar o enunciado

```
render-statement.sh <arquivo-do-enunciado> [formato] [html-dos-exemplos] [título]
```

Escreve o HTML completo no stdout. Usa pandoc com `--mathml` (a matemática vira MathML de verdade) e
`--embed-resources` (as imagens entram embutidas, o HTML é autocontido). Injeta o `<h1>` a partir do
**título**, que é um argumento, e remove um `% Título` legado da primeira linha.

**Este é o único renderizador de enunciado do MOJ.** O botão "Pré-visualizar" do editor, o HTML que o
aluno lê e o que a validação confere passam todos por aqui. Se você precisa mudar como o enunciado é
renderizado, é neste arquivo, e a mudança vale para os três de uma vez. Não crie um segundo pandoc por
fora.

### `gen-report.sh`: o relatório da submissão

```
gen-report.sh <diretório-de-trabalho>
```

Recebe o diretório que o `build-and-test.sh` imprimiu na primeira linha e gera o `report.html`:
veredito, barra de tempo de cada teste em relação ao limite, pico de memória, e o diff colorido entre
o que saiu e o que era esperado. O HTML é autocontido.

Você não costuma chamar este script: o `build-and-test.sh` já o chama no fim.

### `tl-checksum.sh`: o checksum que invalida o tempo-limite

```
tl-checksum.sh <pacote>      # imprime 16 dígitos hexadecimais
```

O checksum cobre **só o que pode mudar o tempo de execução**: o `conf`, os `tests/input/*`, as
`sols/good/*` e o `scripts/*` (conteúdo **e** bit de execução). Não cobre o enunciado, as tags, o
autor nem os `tests/output/*`.

É por isso que **corrigir um typo no enunciado não força recalibração**, mas trocar um teste, uma
solução `good`, o `conf` ou um script força.

### `score-summary.sh`: pontuação por grupos

Não é um comando: é um trecho que o `build-and-test.sh` carrega sozinho quando o pacote tem
`tests/score` (e não tem um `scripts/summary.sh` próprio). Interpreta os grupos, aplica o tudo ou nada
por grupo, soma os pesos e reescreve o veredito com a nota.

### `gen-problem-owners.sh`: o índice de donos (roda no servidor)

Sem argumentos. Varre **todos** os pacotes e escreve
`contests/treino/var/problem-owners.json`, que a gestão de problemas usa para saber, de cada problema:
quem é o dono, em que coleções está, se é público, o checksum atual, quando foi publicado pela
primeira vez, e em quais linguagens existe solução `good`.

Ele mantém um cache por commit de cada problema, para não ter que recalcular o checksum de um pacote
que não mudou.

### `make-sysroot.sh`: construir o rootfs da jaula

```
make-sysroot.sh [--base ubuntu:24.04] [--out DIR] [--tag moj-sysroot] [--pkgs "..."] [--apl arq.deb]
```

Constrói uma imagem com todos os compiladores (a partir de `sysroot/Containerfile`, com podman) e a
exporta para um diretório. Aponte a variável `CAGE_ROOT` para esse diretório e a jaula passa a rodar
dentro dele.

Vale a pena porque o toolchain fica **igual em todas as máquinas de juiz**, e não depende do que
alguém instalou no host.

### `check-deps.sh`: o doutor de dependências

```
check-deps.sh [--rootfs DIR] [--quiet]
```

Diz o que falta na máquina. Sem `--rootfs`, confere os compiladores no `PATH` do host. Com
`--rootfs`, confere os compiladores dentro do rootfs e só o runtime no host. Sai com erro apenas se
faltar dependência **dura**.

### `stress-cage.sh`: testar o sandbox

```
stress-cage.sh [limite-de-memória-em-MB]
```

Seis ataques contra a jaula: fork bomb, alocação infinita, escrita em massa, acesso à rede, leitura do
seu `$HOME` e leitura dos segredos do `/etc`. Imprime PASS ou FAIL para cada um. **Qualquer FAIL
significa que a máquina não deve receber prova hostil.**

### `convert-enunciado.sh`: converter enunciado antigo

```
convert-enunciado.sh <pacote> [--write]
```

Converte um `docs/enunciado.tex` ou `.org` para markdown canônico. Sem `--write` só imprime o
resultado, para você conferir. É uma ferramenta de mão, usada em migração, e o resultado sempre pede
uma revisão humana.

### `Makefile`

| Alvo | O que faz |
|---|---|
| `make help` | lista os alvos |
| `make check` | roda `bash -n` em todos os `.sh` do repositório. **Rode antes de commitar** |
| `make deps` | o `check-deps.sh` |
| `make sysroot` | constrói o rootfs e exporta para um diretório |
| `make sysroot-image` | só a imagem, sem exportar |
| `make sysroot-tar` | um tarball do rootfs, para máquinas que não têm podman |
| `make sysroot-push` | publica a imagem no registry |

## 6. As linguagens (`lang/`)

Cada linguagem aceita é um diretório `lang/<lang>/`, e todas seguem o **mesmo contrato**. Adicionar
uma linguagem é criar um diretório novo, não mexer no julgador.

As 17 linguagens de hoje: `apl`, `c`, `cpp`, `cs`, `go`, `hs`, `java`, `js`, `kt`, `ml`, `pas`, `pl`
(Prolog), `py`, `riscv`, `rs`, `sh`, `spim`.

> **Python é uma linguagem só: `py`**, rodada com **pypy3**. As extensões `.py2` e `.py3` são
> **legadas**: o julgador as normaliza para `py` sozinho. O `lang/py/compile.sh` faz uma checagem de
> sintaxe, então erro de sintaxe em Python vira **Compilation Error**, e não Runtime Error.

### `lang/<lang>/compile.sh`

Roda **dentro da jaula**, num diretório de escrita (`/tmp/rwdir`) que já tem o fonte do aluno.

```sh
exec 2>/tmp/stderrlog > /tmp/out   # stderr vai p/ o log, stdout vai p/ /tmp/out
cd /tmp/rwdir
gcc -O2 -static sol.c -o main      # ... compila ...
echo BIN=main                      # OBRIGATÓRIO
```

**A regra que importa: o script tem que imprimir `BIN=<artefato>` no stdout.** Se não imprimir, o
julgador entende que a compilação falhou e o veredito é **Compilation Error**. É assim que se
implementa "proibir a função `exp()`": o `compile.sh` faz um `grep` no fonte do aluno e, se achar,
sai sem imprimir o `BIN=`.

O tempo-limite da compilação é de 30 segundos. Uma linguagem de compilador lento sobe isso com um
arquivo `lang/<lang>/compile-tl` (em segundos). Hoje só o Kotlin usa (120 segundos, porque a JVM do
`kotlinc` demora a esquentar).

### `lang/<lang>/run.sh`

Roda **dentro da jaula**, com o binário em `/tmp/dir` (só-leitura), a entrada em `/tmp/in` e a saída
em `/tmp/out`.

```sh
exec &>/tmp/stderrlog
cd /tmp/dir
source binfile.sh                  # define BIN, MOJ_MEMLIMITMB, MOJ_STACKKB
exec ./$BIN < /tmp/in > /tmp/out
```

O `binfile.sh` **não é um arquivo deste repositório**: ele é gerado em tempo de execução pelo
`build-and-test.sh`, e é o canal por onde os limites do problema entram na jaula. É por isso que o
`run.sh` do Java consegue dimensionar a JVM com o limite certo:

```sh
exec java -Xmx${MOJ_MEMLIMITMB:-500}m -Xss${MOJ_STACKKB:-131072}k $(basename $BIN .class) < /tmp/in > /tmp/out
```

### `lang/<lang>/prep.sh`

Opcional. É carregado **no host**, fora da jaula, antes de compilar. Só serve para duas coisas: copiar
um arquivo para o diretório de trabalho, e acrescentar um bind à jaula
(`EXTRABINDINGS+=" -b /opt/kotlin"`). Precisa do bit de execução, e **nunca** deve chamar `exit` (use
`return`), porque ele é carregado, não executado.

### `lang/compare.sh`

O comparador **padrão**, usado quando o problema não traz um checker próprio. Compara a saída do
aluno com o gabarito, tolerando cada vez mais diferença, e responde pelo código de saída:

| Código | Significado |
|---|---|
| `4` | as saídas batem exatamente. **Accepted** |
| `5` | batem ignorando espaços em branco e maiúsculas. **Accepted, com erro de formatação** |
| `6` | não batem. **Wrong Answer** |
| outro | erro do próprio comparador. **Erro de juiz** |

Este é o mesmo contrato que um `scripts/compare.sh` de problema tem que cumprir, e ele recebe três
argumentos: `$1` a saída do aluno, `$2` o gabarito, `$3` a entrada.

### `lang-test/`

Uma bateria de fumaça: um "olá, mundo" em cada uma das linguagens, julgado contra um pacote mínimo.

```sh
cd lang-test && make alltests
```

Se alguma linguagem parar de funcionar na máquina, é aqui que aparece primeiro.

## 7. Como um problema customiza o julgamento

O `build-and-test.sh` procura os scripts **do problema antes** dos padrões da linguagem. Essa é a
única coisa que você precisa entender sobre correção especial:

| Ele procura primeiro | Se não achar, usa |
|---|---|
| `<pacote>/scripts/<lang>/compile.sh` | `mojtools/lang/<lang>/compile.sh` |
| `<pacote>/scripts/<lang>/run.sh` | `mojtools/lang/<lang>/run.sh` |
| `<pacote>/scripts/<lang>/prep.sh` | `mojtools/lang/<lang>/prep.sh` |
| `<pacote>/scripts/compare.sh` | `mojtools/lang/compare.sh` |
| `<pacote>/scripts/summary.sh` | `mojtools/score-summary.sh` (se houver `tests/score`) |

É só isso. Submissão de função, ban de função da biblioteca, checker com tolerância, problema
interativo: tudo é alguma combinação dessa tabela. Os detalhes estão em
**[docs/correcao-especial.md](docs/correcao-especial.md)**.

Lembre que **qualquer** mexida em `scripts/` muda o checksum do pacote e dispara recalibração no
juiz.

## 8. Mapa do repositório

| Diretório | O que é |
|---|---|
| `lang/` | uma pasta por linguagem aceita, todas com o mesmo contrato (seção 6) |
| `lang-test/` | o "olá, mundo" de cada linguagem, para conferir a máquina |
| `interactive/` | o driver comum dos problemas interativos, mais o instalador. Técnico: `interactive/README.md` |
| `testlib/` | a testlib vendorada, a ponte de compilação e o instalador de checker. Técnico: `testlib/README.md` |
| `script-templates/` | templates de correção especial que o editor web oferece num seletor. Criar um template é criar uma pasta aqui |
| `kattis/` | importar e exportar problemas no formato Kattis (usado no ICPC). Ver `kattis/README.md` |
| `sysroot/` | a receita do rootfs com os compiladores (`Containerfile`) |
| `docs/` | os guias de autoria: correção especial, checker testlib, problema interativo |

### Documentação

- **[SANDBOX.md](SANDBOX.md)**: como a jaula funciona, como escolher a raiz, o endurecimento.
- **[docs/correcao-especial.md](docs/correcao-especial.md)**: `scripts/` por problema.
- **[docs/checker-testlib.md](docs/checker-testlib.md)**: escrever um checker.
- **[docs/problema-interativo.md](docs/problema-interativo.md)**: escrever um problema interativo.
- **`cdmoj/docs/PACOTE.md`** (no repositório `cdmoj`): o **formato do pacote**, orgs, coleções e
  metadados. É a referência.
- **`cdmoj/docs/FLOW.md`**: o caminho de uma submissão, do browser até o placar.

### Antes de commitar

```sh
make check          # bash -n em todos os .sh
```

Licença: GPLv3 ou posterior. Ver [LICENSE](LICENSE).
