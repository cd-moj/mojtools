OLAMUNDOS=$(wildcard ./OlaMundo/*)
LANGS=$(patsubst ./OlaMundo/OlaMundo.%,%,${OLAMUNDOS})

alltests: $(patsubst %,%.pass,${LANGS})

%.pass:
	@printf "::$(patsubst %.pass,%,$@) "
	@-(../build-and-test.sh $(patsubst %.pass,%,$@) OlaMundo/OlaMundo.$(patsubst %.pass,%,$@) ./template/ > /tmp/mojtools-lang-test 2>&1 && echo Ok && touch $@) || (printf check && cat /tmp/mojtools-lang-test && false)

clean:
	@rm *pass
