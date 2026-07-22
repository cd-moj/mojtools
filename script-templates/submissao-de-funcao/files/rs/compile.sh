#!/bin/bash
# Driver de submissão-de-função (Rust) — TEMPLATE. O arquivo do aluno entra por include!
# (textual); o main é este. EDIT-ME: leitura e chamada. #![allow(non_snake_case)] permite
# nomes de função em camelCase PT. Guia: mojtools/docs/submissao-de-funcao.md
#
# O driver lê a stdin INTEIRA de uma vez; a SENTINELA (última linha 424242 de todo teste)
# confere a estrutura da entrada. ATENÇÃO ao heredoc NÃO-quotado (<<EOF): ele interpola
# $STU de propósito — não troque por <<'EOF'.
exec 2>/tmp/stderrlog > /tmp/out
cd /tmp/rwdir

STU=$(ls *.rs 2>/dev/null | grep -v '^__judge' | head -1)

cat > __judge_run.rs <<EOF
#![allow(non_snake_case)]
include!("$STU");
use std::io::Read;
fn main(){
    let mut __s = String::new();
    std::io::stdin().read_to_string(&mut __s).unwrap();
    let __v: Vec<&str> = __s.split_whitespace().collect();
    let mut __i = 0usize;
    let n: usize = __v[__i].parse().unwrap(); __i += 1;
    for _ in 0..n {
        let a: i32 = __v[__i].parse().unwrap();          // EDIT-ME: leitura
        let b: i32 = __v[__i+1].parse().unwrap(); __i += 2;
        println!("{}", soma(a, b));                       // EDIT-ME: chamada + impressão
    }
    if __i >= __v.len() || __v[__i] != "424242" {         // a entrada casa com o esperado?
        println!("SENTINELA-VIOLADA (entrada malformada ou consumida)");
    }
}
EOF

rustc -C opt-level=3 __judge_run.rs -o main && echo BIN=main
