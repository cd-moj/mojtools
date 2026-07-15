# Jaula (cage-run.sh): raiz do sistema ou rootfs específico

A jaula `bwrap` (`cage-run.sh`) que isola cada compilação/execução pode usar **duas raízes**:

- **Rootfs reprodutível (padrão no juiz)** — a jaula monta um **rootfs inteiro como `/`** (ex.:
  Ubuntu 24.04 com todos os compiladores das linguagens aceitas). Toolchain **reprodutível e igual
  em todo juiz**, independente do SO do host. O `moj-agent` usa o **`$HOME/moj-sysroot` já montado**
  (o operador provisiona/monta; o agente **não recria**); também dá p/ ligar pelo flag `-R` do cage-run.
  **Como provisionar** (o `judge/install.sh` faz por você): `make sysroot` (build+export local),
  ou `make sysroot-tar` → tarball zstd p/ máquinas **sem podman** (C3SL), ou `make sysroot-push` →
  imagem OCI `ghcr.io/cd-moj/moj-sysroot` que o juiz puxa (`install.sh --sysroot pull`). Ver o `Makefile`.
  Se faltar, `AGENT_BUILD_ROOTFS=1` manda construir com `make-sysroot.sh` (precisa podman).
- **Raiz do sistema (host) — opt-out** — a jaula monta `/usr`, `/lib`, `/bin`, … do **host**. O
  toolchain é o do host (não reprodutível); use só p/ depurar ou onde não dá p/ construir o rootfs.
  No juiz: `CAGE_ROOT=host`. (`cage-run.sh` puro, sem o agente, ainda usa o host com `CAGE_ROOT` vazio.)

Só o **userland** (`/usr`,`/lib`,`/etc/…`,compiladores) vem da raiz escolhida; o **IO** (submissão,
testes, script, logs) e os mounts dinâmicos (`/proc`,`/dev`,`/tmp`,`/var`,`/run`) são sempre
sobrepostos do host. ulimits/shield/uid 65534/`--unshare-all`/verdito: inalterados.

**/etc entra INTEIRO** (da raiz escolhida, ro) **com máscaras por cima**: `--ro-bind /dev/null`
em `shadow`/`gshadow`/`*-`/`sudoers`/`machine-id`/`krb5.keytab` e `--tmpfs` em `sudoers.d`/
`ssh`/`ssl/private`; `passwd`+`group` são SOBREPOSTOS por versões sintéticas de 1 linha (uid
65534) no modo host. Assim toolchains acham o que precisam (`alternatives`, `ld.so.conf.d`,
`java.security`, `mono`, `fpc.cfg`, `localtime`) sem binds pontuais por linguagem — a classe
de bug "Can't mkdir /etc/... (read-only)" (mountpoint inexistente na outra raiz) morreu. Os
`prep.sh` só bindam o que NÃO é /etc (`/opt/kotlin`, `/opt/mdyalog`, `/var/lib/ghc`).

## Como escolher a raiz

| Onde | Como | Efeito |
|---|---|---|
| Global do juiz (**padrão**) | nada — o `moj-agent` usa o `$HOME/moj-sysroot` já montado | toda jaula usa o rootfs |
| Forçar o host (opt-out) | `CAGE_ROOT=host` no `agent.env` | toda jaula usa o toolchain do host |
| Caminho fixo do rootfs | `CAGE_ROOT=/srv/moj-sysroot` no `agent.env` | aponta p/ outro rootfs já pronto |
| Construir se faltar | `AGENT_BUILD_ROOTFS=1` no `agent.env` (precisa podman) | o agente roda `make-sysroot.sh` |
| Por linguagem | `CAGE_ROOT_<LANG>=…` (ex.: `CAGE_ROOT_JAVA`, `CAGE_ROOT_PY`) | sobrescreve só aquela linguagem |
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
bash make-sysroot.sh --apl ./dyalog.deb --out /srv/full   # + APL (Dyalog, .deb proprietário)
export CAGE_ROOT=/srv/moj-sysroot                     # aí é só apontar a jaula
```

O `Containerfile` instala o **core** (sempre: `time`,`coreutils`,`bash`,`make`, `build-essential`,
**`bison`+`flex`** — o curso de compiladores submete lex/yacc —, `openjdk-21`, `python3`+`pypy3`) e os
**extras** best-effort (Pascal, Mono/C#, Go/gccgo, Rust, GHC,
Node, OCaml, SWI-Prolog, SPIM). **PyPy3 é o `python3` padrão** do juiz (symlink em `/usr/local/bin`,
mantendo o CPython do sistema p/ o apt). Casos especiais: **APL** (Dyalog proprietário, via `--apl`
— camada extra; o `postinst` do `.deb` cria `/usr/bin/dyalogscript` por `update-alternatives`, e é
esse binário que o `lang/apl/run.sh` chama, sem fixar a versão no caminho),
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
  `-M max(600, MEMLIMITMB+64)` p/ a execução (root e sem root — o cgroup v1 do root também
  respeita) e `-M ${COMPILEMEMLIMIT:-2048}` p/ a **compilação** (kotlinc/JVM passam de 600MB).
- **Modo ROOT é single-slot only.** O caminho root (cset/cgroup v1) usa estado GLOBAL da
  máquina: o `cset shield` é um só e o cgroup de memória, embora agora tenha **nome único por
  invocação** (`mojtools.$$`, removido no fim), não muda o fato de o shield ser compartilhado.
  Jamais rode um juiz **particionado** (multi-slot) como root — o agente força 1 slot nesse
  caso. Produção roda o agente como usuário comum (caminho cgroup v2 acima, escopo por
  invocação, seguro p/ N slots).
- **JVM respeita o MEMLIMITMB:** o `binfile.sh` (que todo `run.sh` sourceia) carrega
  `MOJ_MEMLIMITMB`/`MOJ_STACKKB` p/ dentro da jaula; `lang/java`, `lang/kt` e o driver
  interativo dimensionam **`-Xmx = MEMLIMITMB`** (heap tão grande quanto o limite; 500m sem
  limite definido) e **`-Xss = stack do problema`** (threads da JVM não obedecem o `ulimit -s`).
  O veredito MLE continua sendo o RSS medido vs MEMLIMITMB; a folga de +64MB no cgroup evita
  que o overhead da JVM vire RE por OOM. Pacotes interativos com driver COPIADO antes desta
  mudança mantêm `-Xmx500m` até reinstalar o driver (`install-interactive.sh`).
- **Stack: default 128MB p/ TODAS as linguagens** (`ULIMITS[-s]=131072`, rlimit herdado através
  do bwrap). Override por conf: **`STACKLIMITMB=<MB>`** (preferido, simétrico ao MEMLIMITMB;
  vence) ou `ULIMITS[-s]=<KB>` (ajuste fino). Nota: o `node` (js) tem stack própria da V8,
  independente do rlimit — fora do escopo por ora.
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
