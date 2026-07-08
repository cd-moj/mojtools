#include "testlib.h"
// EXEMPLO: valor inteiro único e exato — adapte (guia: mojtools/docs/checker-testlib.md)
int main(int argc, char* argv[]) {
    registerTestlibCmd(argc, argv);
    // inf = entrada do teste; ouf = saída do participante; ans = saída esperada
    long long esperado = ans.readLong();
    long long recebido = ouf.readLong(-1'000'000'000LL, 1'000'000'000LL, "resposta");
    if (esperado != recebido)
        quitf(_wa, "esperado %lld, veio %lld", esperado, recebido);
    quitf(_ok, "resposta = %lld", recebido);
}
