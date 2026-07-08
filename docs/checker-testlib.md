# Montando problemas com checker testlib no MOJ — guia de autoria

Este é o guia para escrever um **corretor especial (checker)** usando a
[testlib](https://github.com/MikeMirzayanov/testlib) — o padrão do
Codeforces/Polygon — e colocá-lo num pacote de problema do MOJ. A parte
técnica (bridge, cache, exit codes) está em [`../testlib/README.md`](../testlib/README.md);
a mecânica geral de `scripts/` está em [`correcao-especial.md`](correcao-especial.md).

## Quando você precisa de um checker (e quando não)

**NÃO precisa** de checker quando a resposta é única e determinística: o comparador
default do MOJ (`lang/compare.sh`) já faz diff tolerante a espaçamento — e nesse caso
ele ainda distingue `Accepted,PE` (resposta certa com espaçamento diferente).

**Precisa** de checker quando:
- há **múltiplas respostas válidas** (qualquer caminho mínimo, qualquer permutação, …);
- a resposta é **numérica com tolerância** (ponto flutuante);
- é preciso **validar a resposta contra a entrada** (ex.: "é uma solução viável?"),
  e não contra um gabarito fixo;
- o formato exige leitura estruturada (N linhas, depois N valores, …).

## Anatomia de um checker testlib

O checker é um `checker.cpp` **testlib padrão** — sem `#define` especial, sem adaptação
BOCA, sem embutir `testlib.h` no pacote (a testlib vendorada do mojtools é usada
automaticamente). Um checker de Polygon funciona copiado e colado.

```cpp
#include "testlib.h"

int main(int argc, char* argv[]) {
    registerTestlibCmd(argc, argv);
    // três streams:
    //   inf = a ENTRADA do teste       (tests/input/N)
    //   ouf = a saída do PARTICIPANTE
    //   ans = a saída ESPERADA         (tests/output/N)
    long long esperado = ans.readLong();
    long long recebido = ouf.readLong(-1'000'000'000LL, 1'000'000'000LL, "resposta");
    if (esperado != recebido)
        quitf(_wa, "esperado %lld, veio %lld", esperado, recebido);
    quitf(_ok, "resposta = %lld", recebido);
}
```

Leitores mais usados: `readInt(min,max,"nome")`, `readLong`, `readDouble`,
`readToken`/`readWord`, `readLine`, `seekEof()`. Ler com limites (`min,max`) é o que dá
mensagens boas de graça ("integer violates the range") e derruba saída lixo.

### Os quatro finais — e o que viram no MOJ

| chamada | significado testlib | veredicto no MOJ |
|---|---|---|
| `quitf(_ok, …)` | resposta correta | **Accepted** |
| `quitf(_wa, …)` | resposta errada | **Wrong Answer** |
| `quitf(_pe, …)` | saída fora do formato / não parseável | **Wrong Answer** |
| `quitf(_fail, …)` | **o GABARITO/checker está errado** | erro de juiz (UE) — nunca culpa o aluno |

⚠️ **O `_pe` da testlib NÃO é o "PE" do MOJ/BOCA.** No MOJ, `Accepted,PE` significa
"resposta certa, só o espaçamento difere" (e só existe no comparador diff default). O
`_pe` da testlib significa "não consegui nem ler a resposta no formato esperado" — isso
é resposta **errada**, e a bridge o converte em **Wrong Answer, sempre**. Na prática:
use `_wa` para valor errado, `_pe` para formato irrecuperável, e saiba que o aluno verá
Wrong Answer nos dois casos.

Use `_fail` com generosidade dentro da leitura do **`ans`** (o gabarito): se o SEU
gabarito estiver malformado, o veredicto vira erro de juiz visível — e não um WA injusto.

**`quitp()` (pontuação parcial por checker) NÃO é suportado** — vira erro de juiz. No
MOJ, parcial se expressa por **grupos de testes** (`tests/score`); o checker de cada
teste é binário (aceita/rejeita).

## Receitas prontas

### 1. Valor único exato (o caso do `eimp2024-gama`)

```cpp
#include "testlib.h"
int main(int argc, char* argv[]) {
    registerTestlibCmd(argc, argv);
    auto jans = ans.readLong(0, 100'000'000'000LL, "ans");   // gabarito
    auto pans = ouf.readLong(0, 100'000'000'000LL, "ans");   // participante
    if (jans != pans) quitf(_wa, "expected = %lld, got = %lld", jans, pans);
    quitf(_ok, "answer = %lld", pans);
}
```

### 2. Palavra SIM/NÃO, caso-insensível (o caso do `eimp2024-alazao`)

```cpp
#include "testlib.h"
#include <algorithm>
static std::string lower(std::string s){ std::transform(s.begin(),s.end(),s.begin(),::tolower); return s; }
int main(int argc, char* argv[]) {
    registerTestlibCmd(argc, argv);
    std::string jans = lower(ans.readToken());
    std::string pans = lower(ouf.readToken());
    if (jans != "sim" && jans != "nao") quitf(_fail, "gabarito inválido: '%s'", jans.c_str());
    if (pans != "sim" && pans != "nao") quitf(_pe, "esperado SIM/NAO, veio '%s'", pans.c_str());
    if (jans != pans) quitf(_wa, "esperado %s, veio %s", jans.c_str(), pans.c_str());
    quitf(_ok, "%s", pans.c_str());
}
```

### 3. Ponto flutuante com tolerância

```cpp
#include "testlib.h"
int main(int argc, char* argv[]) {
    registerTestlibCmd(argc, argv);
    const double EPS = 1e-6;
    double jans = ans.readDouble();
    double pans = ouf.readDouble();
    if (!doubleCompare(jans, pans, EPS))     // |a-b| <= EPS*max(1,|a|,|b|) — erro rel/abs
        quitf(_wa, "esperado %.10f, veio %.10f (eps=%g)", jans, pans, EPS);
    quitf(_ok, "%.10f", pans);
}
```

### 4. Múltiplas respostas válidas (valida contra a ENTRADA)

Quando qualquer solução viável vale, o gabarito serve só de referência de valor ótimo —
a resposta do participante é validada contra a **entrada** (`inf`):

```cpp
#include "testlib.h"
// entrada: n e um vetor; resposta: um índice i tal que v[i] é máximo
int main(int argc, char* argv[]) {
    registerTestlibCmd(argc, argv);
    int n = inf.readInt();
    std::vector<long long> v(n);
    for (auto &x : v) x = inf.readLong();
    long long best = *std::max_element(v.begin(), v.end());
    int i = ouf.readInt(1, n, "indice") - 1;         // valida o range de graça
    if (v[i] != best) quitf(_wa, "v[%d]=%lld não é o máximo (%lld)", i+1, v[i], best);
    // confere que o GABARITO também é ótimo — pega gabarito quebrado
    int j = ans.readInt(1, n, "indice") - 1;
    if (v[j] != best) quitf(_fail, "gabarito aponta v[%d]=%lld, mas o máximo é %lld", j+1, v[j], best);
    quitf(_ok, "indice %d, valor %lld", i+1, v[i]);
}
```

## O passo a passo no MOJ

```bash
# 1. escreva o checker (checker.cpp, testlib padrão) e instale no pacote:
bash mojtools/testlib/install-checker.sh <pacote> checker.cpp
#    -> cria scripts/checker.cpp + scripts/compare.sh (a bridge) e roda um smoke
#       (gabarito x gabarito tem de dar Accepted)

# 1b. atalho equivalente pela CLI (localiza o mojtools sozinho; MOJTOOLS_DIR aponta):
moj checker <pacote> checker.cpp

# 2. teste com as suas soluções (good => Accepted, wrong => Wrong Answer):
bash mojtools/build-and-test.sh cpp <pacote>/sols/good/sol.cpp <pacote> y
moj test <pacote> --run          # equivalente pela CLI (todas as good; exige bwrap real)
#    a mensagem do checker aparece no log .compare de cada teste (e no report.html)

# 3. transporte: 'moj push' agora CARREGA scripts/ (round-trip completo — conteúdo, +x e
#    symlinks); 'moj upload <id> <pacote>' (aceita o DIRETÓRIO) segue valendo p/ o tar inteiro:
moj push <pacote>
#    (publique por último; confira depois com 'moj check <id>')
```

O juiz compila o checker sozinho na primeira correção (cache em `.checker-cache/`,
fora do pacote versionado) e recompila quando `scripts/checker.cpp` muda — o que também
muda o checksum do pacote e dispara recalibração, como qualquer mudança de `scripts/`.

## Erros comuns

- **Commitar o binário do checker** como `scripts/compare.sh` (o padrão antigo, ELFs de
  2.7MB). Não faça: o pacote leva só o `checker.cpp`; a bridge compila no juiz.
- **Embutir `testlib.h` no pacote.** Desnecessário — a vendorada do mojtools é usada.
  Só coloque um `scripts/testlib.h` se o problema PRECISAR de uma versão diferente
  (ele tem precedência; o instalador avisa).
- **Literais `int` em `readLong(min,max)`**: `ouf.readLong(0, 1000, "x")` é AMBÍGUO
  nesta versão da testlib (overload signed/unsigned) e não compila — use `0LL, 1000LL`.
- **Esquecer de ler a saída toda**: a testlib acusa "Extra information in the output
  file" (⇒ WA) se sobrar lixo depois do que você leu. É um recurso — mas lembre dele
  ao depurar.
- **Usar `_wa` para gabarito quebrado**: gabarito inválido é `_fail` (erro de juiz),
  nunca WA — o aluno não tem culpa.
- **Cliente antigo sem round-trip**: o `moj push` ATUAL carrega `scripts/`; numa CLI antiga o
  push não envia scripts e o problema fica com o comparador default silenciosamente — atualize
  a CLI ou use `moj upload <id> <dir>`.
- **Trocar a ordem dos streams**: no MOJ a bridge chama a ordem PADRÃO testlib
  (`inf`=entrada, `ouf`=participante, `ans`=gabarito). Não compile com `-DBOCA_SUPPORT`
  nem reordene nada — isso é assunto da bridge.
