#!/bin/bash
# tl-checksum.sh <pkgdir> — imprime um checksum (16 hex) dos arquivos que AFETAM o
# JULGAMENTO de um problema: conf + tests/{input,output,score} + sols/good/* + scripts/*
# (correção especial: compile/run/compare/prep por linguagem).
# Determinístico (nomes ordenados + conteúdo; p/ scripts inclui o MODO/bit de execução).
# Muda se-e-somente-se o TL pode mudar OU o VEREDICTO pode mudar (saída esperada, grupos
# do score, forma de compilar/rodar/comparar) — o juiz usa-o p/ saber quando RE-BAIXAR o
# pacote (e RECALIBRAR), e o MOJ p/ DESCARTAR o tl antigo. tests/output e tests/score não
# mudam o TEMPO das good, mas mudam o veredicto — e o cache do juiz é invalidado por ESTE
# checksum: fora dele, um score/saída corrigido nunca chegava ao juiz (caso obi2026f1pm_aula:
# juiz julgando com tests/score de uma iteração anterior p/ sempre). Enunciado e tags NÃO
# entram. Mudou a cobertura? re-stampar os checksums guardados (run/tl/*.json) em vez de
# recalibrar tudo — o pacote não mudou, só a função de hash.
#   uso: tl-checksum.sh <pkgdir>                ->  ex.: 3f9a1c0b8e7d6a5b
#
# `--all-sols` = VERSÃO DO PACOTE (pkg_version): o mesmo stream mais `sols/` INTEIRO (pass, slow,
# wrong, upcoming). É a chave com que o JUIZ decide re-baixar o pacote e a identidade de uma
# calibração. Por que separada: o checksum de cima só pode mudar quando o TL/veredicto muda (senão
# o contest esconde o tempo-limite até alguém recalibrar), mas TODA mexida em solução tem de chegar
# ao juiz — sem isto ele recalibrava o `sols/` do cache velho, julgando solução apagada e ignorando
# a nova (relato do Arthur Botelho, 2026-09-20: o mesmo checksum em 3 juízes com 3 conjuntos
# diferentes de solução).
#   uso: tl-checksum.sh --all-sols <pkgdir>
# O validador de entrada (scripts/validator.cpp) entra só na versão do pacote (ver o laço de scripts).
set -u
ALL_SOLS=0
[[ "${1:-}" == --all-sols ]] && { ALL_SOLS=1; shift; }
pkg="${1:?uso: tl-checksum.sh [--all-sols] <pkgdir>}"
[[ -d "$pkg" ]] || { echo "tl-checksum: pacote inexistente: $pkg" >&2; exit 1; }
SOLDIRS=(sols/good)
(( ALL_SOLS )) && SOLDIRS+=(sols/pass sols/slow sols/wrong sols/upcoming)
{
  # conf: calibrafactor/ULIMITS/CALIBRATIONTL/ALLOWPARALLELTEST/etc. mudam o TL. A linha SAMPLE
  # (exemplos no enunciado, statement-langs.sh) NÃO muda julgamento nem TL: fica de fora, senão
  # marcar "sem exemplos" pediria recalibração e o TL sumiria da prova até o juiz refazer. Só
  # filtra quando a linha EXISTE (conf sem SAMPLE dá o MESMO hash de antes, byte a byte — 1.500
  # pacotes carimbados), e com `sed`, não `grep -v`: o grep repõe o \n final que falte e mudaria o
  # hash de conf sem \n no fim. Por isso quem ACRESCENTA a linha num conf assim a põe no COMEÇO
  # (server/bin/sample-flag-migrate.sh); o editor/API já normalizam o \n final ao gravar.
  # FUNCTION_LANGS (as linguagens de SUBMISSÃO DE FUNÇÃO, cdmoj/docs/PACOTE.md) também fica de fora
  # pelo mesmo motivo: ela só diz ao EDITOR que ali o aluno escreve só a função — quem julga é o
  # scripts/<lang>/compile.sh, e ele já entra no hash (server/bin/function-langs-migrate.sh).
  if [[ -f "$pkg/conf" ]]; then printf '=conf\n'
    if grep -qE '^[[:space:]]*(SAMPLE|FUNCTION_LANGS)[[:space:]]*=' "$pkg/conf"; then sed -E '/^[[:space:]]*(SAMPLE|FUNCTION_LANGS)[[:space:]]*=/d' "$pkg/conf"
    else cat "$pkg/conf"; fi
    printf '\n'; fi
  # testes (entrada + saída esperada + grupos do score) + soluções "good".
  # Em tests/output, arquivo VAZIO ≡ AUSENTE (find -size +0c): interativo puro não tem
  # saída esperada (o árbitro corrige) e um push que materializasse outputs vazios mudava
  # o hash ⇒ recalibração espúria eterna. Vazio não muda veredicto nem TL de ninguém:
  # p/ quem compara com diff, expected vazio ausente e presente são o mesmo julgamento.
  for d in tests/input tests/output tests/score "${SOLDIRS[@]}"; do
    if [[ -f "$pkg/$d" ]]; then   # tests/score é ARQUIVO
      printf '=%s\n' "$d"; cat "$pkg/$d"; printf '\n'; continue
    fi
    [[ -d "$pkg/$d" ]] || continue
    sz=(); [[ "$d" == tests/output ]] && sz=(-size +0c)
    while IFS= read -r f; do
      printf '=%s\n' "${f#"$pkg"/}"; cat "$f"; printf '\n'
    done < <(find "$pkg/$d" -type f "${sz[@]}" 2>/dev/null | LC_ALL=C sort)
  done
  # scripts de correção especial (compile/run/compare/prep por linguagem): mudam a
  # COMPILAÇÃO/EXECUÇÃO/comparação das soluções — logo podem mudar o TL e EXIGEM que o
  # juiz re-baixe o pacote. Inclui o MODO (bit de execução, ex.: chmod +x do compile.sh).
  # EXCEÇÃO: scripts/validator.cpp (o validador de ENTRADA, testlib/validator-run.sh) não julga
  # solução nenhuma — fica FORA do carimbo estreito (mexer nele não pede recalibração nem esconde o
  # TL da prova) e DENTRO da versão do pacote (--all-sols: o juiz tem de baixar o validador novo
  # para a próxima calibração rodá-lo). Pacote sem o arquivo dá o mesmo hash de antes.
  if [[ -d "$pkg/scripts" ]]; then
    while IFS= read -r f; do
      (( ALL_SOLS )) || [[ "$f" != "$pkg/scripts/validator.cpp" ]] || continue
      printf '=%s mode=%s\n' "${f#"$pkg"/}" "$(stat -c '%a' "$f" 2>/dev/null)"; cat "$f"; printf '\n'
    done < <(find "$pkg/scripts" -type f 2>/dev/null | LC_ALL=C sort)
  fi
} | sha256sum | cut -c1-16
