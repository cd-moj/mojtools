#!/bin/bash
# Driver de submissão-de-função (Java) — TEMPLATE. O aluno envia `public class Main` com o
# MÉTODO ESTÁTICO pedido (ex.: static int soma(int a, int b)); a classe Judge (esta) tem o
# main, lê a entrada e chama Main.soma(...). EDIT-ME: leitura e chamada.
# Guia: mojtools/docs/submissao-de-funcao.md
#
# SENTINELA anti-IO: última linha de todo teste é 424242; se o método do aluno consumir a
# entrada (Scanner próprio), a leitura dessincroniza => SENTINELA-VIOLADA => WA.
# Float? imprima com String.format(java.util.Locale.US, "%.6f", x) p/ casar com o C.
cat > /tmp/rwdir/Judge.java <<'EOF'
import java.util.Scanner;
public class Judge {
    public static void main(String[] args){
        Scanner sc = new Scanner(System.in);
        int n = Integer.parseInt(sc.next());
        for (int i = 0; i < n; i++) {
            int a = Integer.parseInt(sc.next());          // EDIT-ME: leitura
            int b = Integer.parseInt(sc.next());
            System.out.println(Main.soma(a, b));          // EDIT-ME: chamada + impressão
        }
        String sentinela = sc.hasNext() ? sc.next() : "";  // a funcao do aluno leu a entrada?
        if (!sentinela.equals("424242")) {
            System.out.println("SENTINELA-VIOLADA (a funcao consumiu a entrada?)");
        }
    }
}
EOF

exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

export _JAVA_OPTIONS="-Xmx300M -Xms50M -Xss10M"
javac *.java && echo BIN=Judge.class
