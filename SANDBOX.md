# Jaula (cage-run.sh): raiz do sistema ou rootfs específico

A jaula `bwrap` (`cage-run.sh`) que isola cada compilação/execução pode usar **duas raízes**:

- **Rootfs reprodutível (padrão no juiz)** — a jaula monta um **rootfs inteiro como `/`** (ex.:
  Ubuntu 24.04 com todos os compiladores das linguagens aceitas). Toolchain **reprodutível e igual
  em todo juiz**, independente do SO do host. O `moj-agent` usa o **`$HOME/moj-sysroot` já montado**
  (o operador provisiona/monta; o agente **não recria**); também dá p/ ligar pelo flag `-R` do cage-run.
  Se faltar, `AGENT_BUILD_ROOTFS=1` manda construir com `make-sysroot.sh` (precisa podman).
- **Raiz do sistema (host) — opt-out** — a jaula monta `/usr`, `/lib`, `/bin`, … do **host**. O
  toolchain é o do host (não reprodutível); use só p/ depurar ou onde não dá p/ construir o rootfs.
  No juiz: `CAGE_ROOT=host`. (`cage-run.sh` puro, sem o agente, ainda usa o host com `CAGE_ROOT` vazio.)

Só o **userland** (`/usr`,`/lib`,`/etc/…`,compiladores) vem da raiz escolhida; o **IO** (submissão,
testes, script, logs) e os mounts dinâmicos (`/proc`,`/dev`,`/tmp`,`/var`,`/run`) são sempre
sobrepostos do host. ulimits/shield/uid 65534/`--unshare-all`/verdito: inalterados.

## Como escolher a raiz

| Onde | Como | Efeito |
|---|---|---|
| Global do juiz (**padrão**) | nada — o `moj-agent` usa o `$HOME/moj-sysroot` já montado | toda jaula usa o rootfs |
| Forçar o host (opt-out) | `CAGE_ROOT=host` no `agent.env` | toda jaula usa o toolchain do host |
| Caminho fixo do rootfs | `CAGE_ROOT=/srv/moj-sysroot` no `agent.env` | aponta p/ outro rootfs já pronto |
| Construir se faltar | `AGENT_BUILD_ROOTFS=1` no `agent.env` (precisa podman) | o agente roda `make-sysroot.sh` |
| Por linguagem | `CAGE_ROOT_<LANG>=…` (ex.: `CAGE_ROOT_JAVA`, `CAGE_ROOT_PY3`) | sobrescreve só aquela linguagem |
| Por problema | `CAGE_ROOT=…` no `conf` do problema | sobrescreve só aquele problema |
| Manual | `cage-run.sh -R /srv/moj-sysroot …` | uso direto/avulso |

Precedência (em `build-and-test.sh`): `CAGE_ROOT_<LANG>` > `conf` do problema > `CAGE_ROOT` global
> (vazio = raiz do host). No **juiz**, o `moj-agent` (`ensure_rootfs`) já define `CAGE_ROOT` =
`$HOME/moj-sysroot` por padrão (já montado; não recria); `CAGE_ROOT=host` força o host. Fora do
agente, vazio = host (inalterado).

## Construir o rootfs (`make-sysroot.sh`)

Requer **podman** (rootless, sem root). Constrói a partir de um `Containerfile` e **exporta** p/ um
diretório:

```bash
bash make-sysroot.sh --out /srv/moj-sysroot          # Ubuntu 24.04 + todos os compiladores
bash make-sysroot.sh --base debian:12 --out /srv/d12 # outra base
bash make-sysroot.sh --pkgs "" --out /srv/core       # só o core (C/C++/Java/Python/PyPy3), rápido
bash make-sysroot.sh --apl ./dyalog_19.0.deb --out /srv/full   # + APL (Dyalog, .deb proprietário)
export CAGE_ROOT=/srv/moj-sysroot                     # aí é só apontar a jaula
```

O `Containerfile` instala o **core** (sempre: `time`,`coreutils`,`bash`,`make`, `build-essential`,
`openjdk-21`, `python3`+`pypy3`) e os **extras** best-effort (Pascal, Mono/C#, Go/gccgo, Rust, GHC,
Node, OCaml, SWI-Prolog, SPIM). **PyPy3 é o `python3` padrão** do juiz (symlink em `/usr/local/bin`,
mantendo o CPython do sistema p/ o apt). Casos especiais: **APL** (Dyalog proprietário, via `--apl`),
**RISC-V** (só precisa do JDK; o `rars.jar` é baixado pelo `prep`). **Python é UMA linguagem: `py`**
(interpretador **pypy3**, com fallback `python3` no modo host; o `compile.sh` faz **check de sintaxe**
via `py_compile` — erro de sintaxe = Compilation Error). `py2` foi **removido**; `.py2`/`.py3` são
extensões legadas normalizadas p/ `py` (o lang-dir `py3` é só um symlink de compat).

> O **runtime da jaula** (`/usr/bin/time`, `timeout`, `bash`) roda **dentro** do rootfs — por isso o
> core inclui `time`/`coreutils`/`bash` além dos compiladores.

## Hardening para prova (competidores adversários)

- **Limite de memória DURO sem root (cgroup v2):** com `-M <MB>` e agente rodando como usuário
  comum, o `cage-run.sh` envolve o bwrap num scope `systemd-run --user --scope -p MemoryMax=<MB>M
  -p MemorySwapMax=0` — alocação desenfreada morre NA HORA (antes só existia o MLE por RSS medido
  **depois** da execução, que não contém um estouro rápido). Sem user manager (CI/containers), o
  cage degrada com aviso no stderr p/ o comportamento clássico. O `build-and-test.sh` passa
  `-M max(600, MEMLIMITMB+64)` p/ a execução e `-M ${COMPILEMEMLIMIT:-2048}` p/ a **compilação**
  (kotlinc/JVM passam de 600MB). Como root, vale o caminho cset/cgroup v1 de sempre.
- **Bateria de estresse (`stress-cage.sh`):** rode **num juiz real** antes de prova hostil —
  fork-bomb, OOM, escrita em massa, rede, leitura do `$HOME`. Qualquer FAIL = não use a máquina.
  `bash stress-cage.sh [MEM_MB]` (usa `CAGE_ROOT` se setado).
- **seccomp (pendente):** o bwrap aceita `--seccomp <fd>` mas exige um **programa BPF compilado**
  (não há DSL embutida) — gerar/manter esse filtro é trabalho à parte e um filtro errado derruba
  TODO o julgamento. Mitigação atual: `--unshare-all` (sem rede/pid/ipc), uid 65534, rootfs RO,
  ulimits + cgroup acima. Se um perfil seccomp for adotado no futuro, valide com a bateria acima
  e uma rodada completa de calibração antes de qualquer prova.

## Notas

- **Tamanho/tempo:** o rootfs completo (com GHC etc.) tem alguns GB e o build baixa bastante; rode
  no host do juiz. `--pkgs ""` gera um rootfs enxuto (core) p/ testar rápido.
- **usrmerge** do Ubuntu (`/bin`→`/usr/bin`, …) resolve sozinho porque a jaula binda o rootfs inteiro
  como `/`.
- **Ambientes Firejail:** onde `bwrap`/userns estão neutralizados (ex.: um shell já dentro do
  Firejail), tanto o `podman build` quanto a execução real da jaula precisam rodar **fora** do
  Firejail (no host do juiz).
