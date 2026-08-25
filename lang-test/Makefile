OLAMUNDOS=$(wildcard ./OlaMundo/*)
LANGS=$(patsubst ./OlaMundo/OlaMundo.%,%,${OLAMUNDOS})

alltests: $(patsubst %,%.pass,${LANGS})

%.pass:
	@printf "::$(patsubst %.pass,%,$@) "
	@-(../build-and-test.sh $(patsubst %.pass,%,$@)	OlaMundo/OlaMundo.$(patsubst %.pass,%,$@) ./template/ > /tmp/mojtools-lang-test 2>&1 && grep -q Accepted /tmp/mojtools-lang-test && echo OK && touch $@) || (printf check && cat /tmp/mojtools-lang-test && false)

## hostile — a MESMA bateria com o nome que o NAVEGADOR produz em download repetido:
## "OlaMundo(1).<lang>". É o caso do relato de 2026-08-24 (`l(1).cpp` dava Compilation Error,
## porque o make entrega o recipe ao /bin/sh cru).
##
## COMO LER: rode `make alltests` ANTES, na mesma máquina, e compare. Linguagem que já falha no
## alltests é toolchain faltando, não este bug. E as duas baterias precisam de bwrap DE VERDADE
## **com o rootfs do juiz** — no dev, onde o fbwrap é no-op, nenhuma das duas roda:
##
##     CAGE_ROOT=$$HOME/moj-sysroot make alltests   # controle
##     CAGE_ROOT=$$HOME/moj-sysroot make hostile    # o mesmo, com o nome hostil
##
## O portão que roda em qualquer máquina é o `make check` da raiz (check-quoting.sh).
##
## ⚠ JAVA E RUST FICAM DE FORA POR DEFINIÇÃO, não por preguiça: nas duas o NOME DO ARQUIVO É
## SEMÂNTICO para o compilador, e nenhuma quantidade de aspas muda isso.
##   java: `javac` exige que o arquivo case com a classe pública;
##   rs:   `rustc` deriva o CRATE NAME do arquivo — "invalid character `'('` in crate name".
## Nos dois, "OlaMundo(1)" é Compilation Error LEGÍTIMO, e quem evita isso é o servidor, que
## normaliza o nome na porta (safe_src_filename, no /submit). Não "conserte" incluindo-os aqui —
## e não passe `--crate-name` fixo no lang/rs p/ forçar: quebraria quem escreve
## `#![crate_name=…]`, trocando um caso que não existe mais por um novo.
HOSTILE_LANGS=$(filter-out java rs,${LANGS})

hostile: $(patsubst %,%.hostile,${HOSTILE_LANGS})

%.hostile:
	@printf ":: $(patsubst %.hostile,%,$@)(1) "
	@mkdir -p hostile-tmp
	@cp "OlaMundo/OlaMundo.$(patsubst %.hostile,%,$@)" "hostile-tmp/OlaMundo(1).$(patsubst %.hostile,%,$@)"
	@-(../build-and-test.sh $(patsubst %.hostile,%,$@) "hostile-tmp/OlaMundo(1).$(patsubst %.hostile,%,$@)" ./template/ > /tmp/mojtools-lang-test 2>&1 && grep -q Accepted /tmp/mojtools-lang-test && echo OK && touch $@) || (printf check && cat /tmp/mojtools-lang-test && false)

clean:
	@rm -f *.pass *.hostile
	@rm -rf hostile-tmp
