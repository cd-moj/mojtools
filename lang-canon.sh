#!/bin/bash
# lang-canon.sh — extensão de arquivo -> linguagem CANÔNICA (o nome do dir em lang/).
# Fonte ÚNICA no mojtools (o cdmoj tem a gêmea em lib/langs.sh `lang_canon_ext`); quem deriva a
# linguagem de `${arquivo##*.}` (build-and-test, calibreitor, validate-problem, gen-problem-owners)
# passa por aqui — antes cada um tinha o próprio `case py2|py3` e nenhum sabia de C++.
#   C++ = cpp, cc, cxx, c++ (e hpp)   |   C = c (e h)   |   Python = py (py2/py3 legadas)
# Uso: `source lang-canon.sh; lang_canon cc` -> cpp   ou   `bash lang-canon.sh cc`.
lang_canon(){
  local t; t="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    c++|cc|cxx|hpp) printf 'cpp';;
    h)              printf 'c';;
    py2|py3)        printf 'py';;
    *)              printf '%s' "$t";;
  esac
}
[[ "${BASH_SOURCE[0]}" == "$0" ]] && lang_canon "${1:-}"
