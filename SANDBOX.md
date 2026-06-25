# Jaula (cage-run.sh): raiz do sistema ou rootfs específico

A jaula `bwrap` (`cage-run.sh`) que isola cada compilação/execução pode usar **duas raízes**:

- **Raiz do sistema (default)** — como sempre: a jaula monta `/usr`, `/lib`, `/bin`, … do **host**.
  Zero configuração, zero regressão. O conjunto de compiladores é o do host.
- **Rootfs específico** — a jaula monta um **rootfs inteiro como `/`** (ex.: Ubuntu 24.04 com
  todos os compiladores das linguagens aceitas). Toolchain **reprodutível e igual em todo juiz**,
  independente do SO do host. Liga-se com a variável **`CAGE_ROOT`** (ou o flag `-R` do cage-run).

Só o **userland** (`/usr`,`/lib`,`/etc/…`,compiladores) vem da raiz escolhida; o **IO** (submissão,
testes, script, logs) e os mounts dinâmicos (`/proc`,`/dev`,`/tmp`,`/var`,`/run`) são sempre
sobrepostos do host. ulimits/shield/uid 65534/`--unshare-all`/verdito: inalterados.

## Como escolher a raiz

| Onde | Como | Efeito |
|---|---|---|
| Global do juiz | `CAGE_ROOT=/srv/moj-sysroot` no `agent.env` (ou ambiente) | toda jaula usa o rootfs |
| Por linguagem | `CAGE_ROOT_<LANG>=…` (ex.: `CAGE_ROOT_JAVA`, `CAGE_ROOT_PY3`) | sobrescreve só aquela linguagem |
| Por problema | `CAGE_ROOT=…` no `conf` do problema | sobrescreve só aquele problema |
| Manual | `cage-run.sh -R /srv/moj-sysroot …` | uso direto/avulso |

Precedência (em `build-and-test.sh`): `CAGE_ROOT_<LANG>` > `conf` do problema > `CAGE_ROOT` global
> (vazio = raiz do host). Vazio em qualquer ponto = comportamento atual.

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
**RISC-V** (só precisa do JDK; o `rars.jar` é baixado pelo `prep`). **py2 não é provisionado** (só
python3/pypy3) — submissões py2 só rodam no modo host (legado).

> O **runtime da jaula** (`/usr/bin/time`, `timeout`, `bash`) roda **dentro** do rootfs — por isso o
> core inclui `time`/`coreutils`/`bash` além dos compiladores.

## Notas

- **Tamanho/tempo:** o rootfs completo (com GHC etc.) tem alguns GB e o build baixa bastante; rode
  no host do juiz. `--pkgs ""` gera um rootfs enxuto (core) p/ testar rápido.
- **usrmerge** do Ubuntu (`/bin`→`/usr/bin`, …) resolve sozinho porque a jaula binda o rootfs inteiro
  como `/`.
- **Ambientes Firejail:** onde `bwrap`/userns estão neutralizados (ex.: um shell já dentro do
  Firejail), tanto o `podman build` quanto a execução real da jaula precisam rodar **fora** do
  Firejail (no host do juiz).
