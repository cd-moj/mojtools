// Validador de ENTRADA (testlib). Confere se cada arquivo de tests/input segue o formato e os limites do
// enunciado. Troque as leituras abaixo pelo formato do SEU problema. Guia: mojtools/docs/validador-testlib.md
//
// Exemplo: a 1ª linha tem N (1 <= N <= 1000); a 2ª tem N inteiros de -10^9 a 10^9 separados por UM espaço.
#include "testlib.h"

int main(int argc, char* argv[]) {
    registerValidation(argc, argv);
    int n = inf.readInt(1, 1000, "N");          // o nome ("N") aparece na mensagem de erro
    inf.readEoln();
    for (int i = 0; i < n; i++) {
        if (i > 0) inf.readSpace();              // exatamente UM espaço entre os números
        inf.readLong(-1000000000LL, 1000000000LL, "a_i");
    }
    inf.readEoln();                              // a última linha termina com \n
    inf.readEof();                               // e não sobra nada depois dela
}
