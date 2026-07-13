# mojtools/Makefile — sandbox: constrói/publica o rootfs da jaula (moj-sysroot) e checa deps.
# O rootfs (sysroot/Containerfile) traz os compiladores das linguagens aceitas. O judge o
# consome por `--sysroot pull` (imagem OCI) ou `--sysroot tar` (tarball, p/ o C3SL sem podman).
#
#   make sysroot                 # build + EXPORTA p/ um diretório (uso local direto)
#   make sysroot-image           # só constrói a imagem OCI (tag moj-sysroot)
#   make sysroot-tar             # imagem -> tarball zstd (artefato p/ máquinas sem podman)
#   make sysroot-push            # publica em ghcr.io/cd-moj/moj-sysroot:<TAG>

SHELL      := /bin/bash
TAG        ?= $(shell date +%Y-%m-%d)
IMAGE      ?= moj-sysroot
REGISTRY   ?= ghcr.io/cd-moj/moj-sysroot
BASE       ?= ubuntu:24.04
OUT        ?= $(HOME)/moj-sysroot
TARFILE    ?= moj-sysroot-$(TAG).tar.zst
# .deb proprietário do Dyalog APL (opcional): make sysroot-image APL=/caminho/dyalog.deb
APL        ?=

.PHONY: help check deps sysroot sysroot-image sysroot-tar sysroot-push

help:
	@sed -n '1,12p' Makefile

## check — bash -n em todos os .sh do repo + bit de execução dos scripts de linguagem/drivers
# O +x de lang/*/{compile,run,compare}.sh é LOAD-BEARING: o cage-run.sh monta cada um como
# /tmp/script (bind READ-ONLY) e o executa DIRETO (`timeout $$TLE /tmp/script`, sem `bash`) — sem o
# bit é "Permission denied", e nem dá p/ consertar de dentro da jaula. Checamos o modo NO ÍNDICE DO
# GIT (é ele que um `clone` materializa; um `chmod` local não viaja). O `kt` nasceu 644 e Kotlin
# (linguagem oficial do ICPC) não rodava em juiz nenhum provisionado do repositório.
# Vale IGUAL p/ os drivers canônicos de testlib/ e interactive/: o juiz EXECUTA o compare.sh do
# pacote direto (fora da jaula) e testa o prep.sh com -x antes do source; e o handler de
# script-templates do cdmoj copia p/ o pacote o bit +x DO ALVO do symlink — stub sem +x = todo
# problema criado pelo editor web nasce dando UE em todos os testes.
check:
	@find . -name '*.sh' -not -path './sysroot/rootfs/*' -print0 | xargs -0 -n1 bash -n \
	  && echo "sintaxe ok"
	@bad="$$(git ls-files -s 'lang/*/compile.sh' 'lang/*/run.sh' 'lang/*/compare.sh' 'lang/compare.sh' \
	         'testlib/checker-bridge.sh' 'testlib/compare-stub.sh' \
	         'interactive/prep.sh' 'interactive/run.sh' 'interactive/compare.sh' \
	         'interactive/summary-score.sh' 'interactive/prep-stub.sh' \
	         'interactive/compare-stub.sh' 'interactive/summary-stub.sh' 2>/dev/null \
	         | awk '$$1 != "100755" { print "    " $$4 }')"; \
	if [ -n "$$bad" ]; then \
	  echo "SEM +x NO GIT (o juiz/a jaula executa o script direto -> Permission denied):"; echo "$$bad"; \
	  echo "  conserte: git update-index --chmod=+x <arquivo>"; exit 1; \
	else echo "bits de execução ok (lang/*, testlib/*, interactive/*)"; fi

## deps — doctor de dependências (host e, com --rootfs, dentro da jaula)
deps:
	bash check-deps.sh $(if $(ROOTFS),--rootfs $(ROOTFS),)

## sysroot — build da imagem + EXPORTA p/ $(OUT) (make-sysroot.sh)
sysroot:
	bash make-sysroot.sh --base $(BASE) --tag $(IMAGE) --out $(OUT) $(if $(APL),--apl $(APL),)

## sysroot-image — só constrói a imagem OCI (sem exportar)
sysroot-image:
	bash make-sysroot.sh --base $(BASE) --tag $(IMAGE) --no-export $(if $(APL),--apl $(APL),)

## sysroot-tar — imagem -> tarball zstd (para máquinas SEM podman: judge --sysroot tar)
sysroot-tar: sysroot-image
	@command -v zstd >/dev/null || { echo "preciso de zstd"; exit 1; }
	cid=$$(podman create $(IMAGE) true); \
	podman export "$$cid" | zstd -q -o $(TARFILE); \
	podman rm "$$cid" >/dev/null 2>&1 || true; \
	echo ">> $(TARFILE) pronto (use: judge/install.sh --sysroot tar --sysroot-tar $(TARFILE))"

## sysroot-push — publica a imagem no registry (precisa `podman login $(REGISTRY)`)
sysroot-push: sysroot-image
	podman tag $(IMAGE) $(REGISTRY):$(TAG)
	podman tag $(IMAGE) $(REGISTRY):latest
	podman push $(REGISTRY):$(TAG)
	podman push $(REGISTRY):latest
	@echo ">> publicado $(REGISTRY):$(TAG) (+ :latest)"
