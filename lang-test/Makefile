OLAMUNDOS=$(wildcard ./OlaMundo/*)
LANGS=$(patsubst ./OlaMundo/OlaMundo.%,%,${OLAMUNDOS})

alltests: $(patsubst %,%.pass,${LANGS})

%.pass:
	@printf "::$(patsubst %.pass,%,$@) "
	@-(../build-and-test.sh $(patsubst %.pass,%,$@)	OlaMundo/OlaMundo.$(patsubst %.pass,%,$@) ./template/ > /tmp/mojtools-lang-test 2>&1 && grep -q Accepted /tmp/mojtools-lang-test && echo OK && touch $@) || (printf check && cat /tmp/mojtools-lang-test && false)

## hostile — a MESMA bateria com o nome que o NAVEGADOR produz em download repetido:
## "OlaMundo(1).<lang>". É o caso do relato de 2026-08-24 (`l(1).cpp` dava Compilation Error,
## porque o make entrega o recipe ao /bin/sh cru). Precisa de bwrap DE VERDADE — no dev, onde o
## fbwrap é no-op, nem o `alltests` roda; isto é bateria de JUIZ.
## O portão que roda em qualquer máquina é o `make check` da raiz (check-quoting.sh).
##
## ⚠ JAVA FICA DE FORA POR DEFINIÇÃO, não por preguiça: `javac` exige que o arquivo case com a
## classe pública, então "OlaMundo(1).java" é Compilation Error LEGÍTIMO. Quem evita isso é o
## servidor, que normaliza o nome na porta (safe_src_filename, no /submit). Não "conserte" isto
## incluindo java aqui.
HOSTILE_LANGS=$(filter-out java,${LANGS})

hostile: $(patsubst %,%.hostile,${HOSTILE_LANGS})

%.hostile:
	@printf ":: $(patsubst %.hostile,%,$@)(1) "
	@mkdir -p hostile-tmp
	@cp "OlaMundo/OlaMundo.$(patsubst %.hostile,%,$@)" "hostile-tmp/OlaMundo(1).$(patsubst %.hostile,%,$@)"
	@-(../build-and-test.sh $(patsubst %.hostile,%,$@) "hostile-tmp/OlaMundo(1).$(patsubst %.hostile,%,$@)" ./template/ > /tmp/mojtools-lang-test 2>&1 && grep -q Accepted /tmp/mojtools-lang-test && echo OK && touch $@) || (printf check && cat /tmp/mojtools-lang-test && false)

clean:
	@rm -f *.pass *.hostile
	@rm -rf hostile-tmp
