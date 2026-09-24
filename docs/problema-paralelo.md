# Problema paralelo: `CPUNEEDED`, `SAMENUMA` e os testes em paralelo

Guia de autoria para problemas cujo teste precisa de **mais de uma CPU** (OpenMP, MPI, pthreads) —
e, de quebra, o que significam `ALLOWPARALLELTEST`/`MAXPARALLELTESTS` para **qualquer** problema.
O formato do pacote (a tabela completa do `conf`) está em `cdmoj/docs/PACOTE.md`, seção "Problemas
paralelos"; aqui está o **como** e o **porquê**.

## 1. Duas coisas diferentes com a mesma palavra

| | O que é | Chave do `conf` |
|---|---|---|
| **Teste paralelo** | UM teste usa **k CPUs** ao mesmo tempo (o programa do aluno é paralelo) | `CPUNEEDED=k`, `SAMENUMA=y` |
| **Testes em paralelo** | o juiz roda **vários testes** da mesma submissão ao mesmo tempo, cada um nas suas CPUs | `ALLOWPARALLELTEST`, `MAXPARALLELTESTS` |

Um problema paralelo é o primeiro caso. O segundo é uma otimização do juiz que vale para todo
problema e **não muda o tempo-limite** de ninguém.

## 2. As chaves

| Chave | Default | Semântica |
|---|---|---|
| `CPUNEEDED=k` | 1 | CPUs que **cada teste** precisa. Inteiro 1..64. Requisito **duro**: o juiz nunca roda um teste com menos; se não tiver k CPUs livres, o teste espera. Mudar força recalibração (o `conf` entra no checksum do pacote) |
| `SAMENUMA=y` | n | com k > 1, as k CPUs de cada teste ficam **no mesmo nó NUMA** (memória local; importa para programas que batem em memória compartilhada) |
| `ALLOWPARALLELTEST` | ligado (ausente = `y`) | `y` = o juiz **pode** rodar vários testes ao mesmo tempo, cada um nas suas k CPUs, **quando tem CPU ociosa**; `n` = um teste por vez |
| `MAXPARALLELTESTS=m` | o teto do juiz (4) | teto de testes ao mesmo tempo deste problema; nunca passa do teto do juiz |

O `validate-problem.sh` (o botão **Validar**, o `moj test`) reprova valor inválido nas quatro e
avisa quando nenhum juiz registrado tem k CPUs (num nó, com `SAMENUMA=y`).

## 3. Como o juiz executa

Os juízes oficiais são particionados em **slots de 1 CPU** (dezenas por máquina). Um problema comum
ocupa 1 slot por teste. Um problema com `CPUNEEDED=k`:

1. o escalonador só entrega o julgamento a um juiz com **k slots livres** (e, com `SAMENUMA=y`, k
   slots livres **no mesmo nó**);
2. o agente **junta** esses slots num grupo, pina o teste nele (`taskset`; dentro da jaula `nproc`
   = k) e, no fim, **separa** de novo — os slots voltam a servir problemas comuns;
3. a **calibração** roda **um teste por vez, em k CPUs** — o tempo-limite é medido exatamente na
   forma em que cada teste vai rodar no julgamento. Por isso o `TL` de um problema paralelo só vale
   com o mesmo k: mudar `CPUNEEDED` recalibra;
4. com hyperthreading (SMT) e k ≥ 2, o grupo é formado por **núcleos inteiros** (os dois irmãos),
   tanto na calibração quanto no julgamento — um teste nunca divide um núcleo físico com outro.

Quando o juiz tem CPU sobrando e o problema permite (`ALLOWPARALLELTEST`), ele roda **P testes ao
mesmo tempo, cada um no seu grupo de k CPUs** — P sobe e desce com a demanda (fila cheia ⇒ P = 1;
nunca tira CPU de outra submissão; em prova o admin costuma desligar isso). O relatório de cada
submissão diz o que aconteceu: **"Paralelismo: P teste(s) ao mesmo tempo × k CPU(s) por teste"**.

## 4. O que o `run.sh` recebe

O `build-and-test.sh` entrega à jaula, pelo `binfile.sh` (que todo `run.sh` sourceia), dois valores
**exportados**:

- **`MOJ_TEST_CPUS`** = k (ou o que o agente deu ao teste — sempre ≥ `CPUNEEDED`);
- **`OMP_NUM_THREADS`** = o mesmo valor.

Então:

- **OpenMP / pthreads**: normalmente **nada a fazer** no `run.sh` — o OpenMP lê `OMP_NUM_THREADS`
  sozinho, e um programa pthreads que consulta `nproc`/`sysconf(_SC_NPROCESSORS_ONLN)` dentro da
  jaula vê k (a afinidade vale lá dentro). Só o `compile.sh` muda (`-fopenmp`).
- **MPI**: o `run.sh` **tem** de lançar `mpirun -np "$MOJ_TEST_CPUS"` — **nunca um número fixo**.
  O `-np 4` cravado dos pacotes antigos rodava 4 processos numa CPU só, e o TL medido assim não
  tinha relação com o problema.

Os dois templates prontos (seletor do editor web, ou `moj-cli`):

- **`paralelo-openmp`**: `scripts/c/compile.sh` e `scripts/cpp/compile.sh` com `-fopenmp` (o
  `run.sh` padrão da linguagem serve);
- **`paralelo-mpi`**: `compile.sh` com `mpicc`/`mpicxx` (OpenMPI da rootfs; **sem `-static`** — a
  OpenMPI não linka estático) e `run.sh`:

```sh
exec &>/tmp/stderrlog
cd /tmp/dir
source binfile.sh
set -o pipefail
exec mpirun --bind-to none --oversubscribe -np "${MOJ_TEST_CPUS:-1}" ./"$BIN" < /tmp/in > /tmp/out
```

`--bind-to none`: a afinidade já é a do grupo de CPUs do teste (o juiz pinou); deixar a OpenMPI
re-pinar por baixo só atrapalha. `--oversubscribe`: dentro da jaula ela pode contar menos "slots"
do que CPUs. `pipefail`: o código de saída que conta é o do aluno (o `| grep -v UCX` dos pacotes
antigos mascarava um Runtime Error como Accepted/Wrong Answer).

## 5. Receita

1. Crie o problema como qualquer outro (enunciado, testes, `sols/good`).
2. **Limites › Problemas paralelos** no editor (ou `moj edit` › Conf): `CPUNEEDED=k`; ligue
   `SAMENUMA` se o programa depende de memória compartilhada de verdade.
3. **Soluções & Correção › correção › templates**: aplique `paralelo-openmp` ou `paralelo-mpi`;
   restrinja **`languages`** do problema a `c`/`cpp` (sem isso, trocar de linguagem burla o
   esquema: um `.py` cairia no `run.sh` padrão).
4. `conf`: `ULIMITS[-u]=10000` para MPI (o `mpirun` cria processos auxiliares); `MEMLIMITMB` se
   quiser limitar memória — vale para o **conjunto** dos processos do teste.
5. **Validar** (reprova chave inválida; avisa se não há juiz com k CPUs) e **Calibrar**. Na tela da
   calibração, o log do juiz diz "Paralelismo dado pelo agente: 1 teste(s) ao mesmo tempo × k CPU(s)
   por teste".
6. Submeta a `good` como aluno e abra o relatório: **"Paralelismo: … × k CPU(s) por teste"**. Para
   conferir na máquina: `taskset -p <pid>` do processo do aluno mostra a máscara de k CPUs.

## 6. O que muda quando você edita

- `CPUNEEDED`/`SAMENUMA` fazem parte do `conf` ⇒ mudar **recalibra** (o TL de k=2 não vale para k=4).
- `ALLOWPARALLELTEST`/`MAXPARALLELTESTS` também estão no `conf` (mesmo checksum), mas **não mudam
  o tempo medido** — a calibração é sempre um teste por vez.
- Rodar `moj test --run` na sua máquina com menos de k CPUs funciona, com **aviso**: o teste roda
  com menos CPU do que o problema pede e o tempo medido ali não vale como TL.

## 7. Armadilhas

- **`-np` fixo** no `run.sh`, ou `OMP_NUM_THREADS` cravado no `compile.sh`: o programa roda com
  mais threads/processos do que CPUs, o TL calibrado mente. Use sempre `MOJ_TEST_CPUS`.
- **`CPUNEEDED` sem juiz que sirva** (k maior que o maior juiz, ou `SAMENUMA=y` com k maior que o
  maior nó): o julgamento fica na fila até um juiz assim existir; passado um tempo o escalonador
  devolve **Judge Error** com o motivo. O aviso do Validar existe para pegar isso antes.
- **`MAXPARALLELTESTS` não é `CPUNEEDED`**: o primeiro é "quantos testes ao mesmo tempo", o segundo
  "quantas CPUs por teste". Um problema paralelo quase sempre quer `CPUNEEDED=k` e pode deixar os
  testes em paralelo como estão (cada teste já tem as suas k CPUs).
- **Juiz como root**: single-slot, sem pin por teste — não serve problema com `CPUNEEDED>1`
  (`SANDBOX.md`).
- **Tempo de parede vs. CPU**: o TL é de **parede** (`real`). Um programa que cria k threads mas
  serializa num lock não vai ficar k vezes mais rápido — a `good` mede o que o autor conseguiu, e é
  isso que vira o limite.

## 8. Testes em paralelo, para qualquer problema

`ALLOWPARALLELTEST` ligado (o default) só diz que o juiz **pode** rodar vários testes desta
submissão ao mesmo tempo quando tem CPU ociosa — cada teste continua sozinho nas suas CPUs, o
tempo de cada um é medido como sempre e um TLE detectado assim é **refeito serialmente** antes de
valer. Desligue (`n`) só se o problema depende de algo compartilhado entre testes fora da jaula
(raríssimo: os testes não veem uns aos outros). `MAXPARALLELTESTS` é um teto por problema; o teto
do juiz (4 por padrão) e a política do admin (em prova, geralmente desligada) valem por cima.
