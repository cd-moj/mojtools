# Migração dos problemas legados → Gitea

Migra os repos legados (`moj-problems/<repo>/`, hoje em gitolite/sr.ht/gitlab) para o **Gitea**,
**preservando a história**, gerando `.moj-meta.json` por problema (dono · público · coleção) e,
opcional, **convertendo os enunciados** (tex/org → Markdown canônico). Incremental, idempotente,
**sem derrubar o treino**: trabalha num **clone temporário** (o checkout NFS não é tocado) e o
treino continua servindo `var/jsons` o tempo todo.

## Modelo
- **1 repo legado → 1 repo Gitea** com **um dono** (curador/professor). A autoria por problema
  fica preservada no arquivo `author` (texto livre) + `.moj-meta.json`.
- **Dono** vem do `author-map.tsv` (`@repo:<repo>` ou `@default`, fallback `curador`).
- **Público** = `conf` **sem** `PUBLIC=no`. **Coleção** = `[<repo>]` (o diretório é a coleção).
- **IDs estáveis**: continua `<repo>#<problema>` — nada quebra nos ~1100 ids nem nos `var/jsons`.

## Passo a passo
```bash
cd /home/ribas/moj
export MOJ_PROBLEMS_DIR=$PWD/moj-problems CONTESTSDIR=$PWD/contests RUNDIR=$PWD/run

# 1) levanta os autores e CURA o mapa (dono por repo + logins frequentes)
bash mojtools/migrate/author-survey.sh authors.tsv      # 332 autores -> authors.tsv
$EDITOR mojtools/migrate/author-map.tsv                  # ajuste @repo:* e os logins

# 2) DRY-RUN por repo (não muda nada) e revise o plano
bash mojtools/migrate/migrate-repo.sh saad-problems
column -t -s$'\t' migration-report.tsv | less

# 3) PILOTO num repo pequeno: gera meta, converte, e empurra p/ o Gitea (história preservada)
bash mojtools/migrate/migrate-repo.sh compiladores-problems --write --convert --push

# 4) confira no Gitea + na UI de gestão (o dono já aparece pelo registro de diretórios)
#    (o índice de donos passa a mostrar owner=<curador> p/ os problemas do repo migrado)

# 5) expanda curso a curso (eda2, flia, monitores, saad, problemas-apc, obi, moj-problems)
```

## Repointar o NFS p/ o Gitea (POR ÚLTIMO — reversível)
Enquanto não repointar, o `--push` só popula o Gitea; o treino segue servindo o `var/jsons`
gerado do checkout NFS atual. Quando um repo estiver **migrado e conferido**, vire o `origin`:
```bash
cd moj-problems/<repo>
git remote -v                                  # anote o origin atual (p/ reverter)
src=$(cat /home/ribas/moj/run/gitea/.port)     # porta do Gitea
git remote set-url origin http://<owner>@localhost:$src/<owner>/<repo>.git
git pull                                        # traz .moj-meta.json + conversões
```
Reverter = `git remote set-url origin <url-antigo>`. O `.moj-meta.json` em NFS faz o
`gen-problem-owners.sh` refletir dono/coleção por problema (antes disso, o **registro de
diretórios** `problem-repos.json` já dá o dono do repo).

## Repos espalhados (sr.ht + gitlab + gitolite)
```bash
bash mojtools/migrate/consolidate-remotes.sh moj-problems/<repo> \
     srht=git@git.sr.ht:~bcribas/<repo> gitolite=git@chococino.naquadah.com.br:<repo>
git -C moj-problems/<repo> log --all --oneline | head    # revise antes de migrar
```

## Conversão de enunciados (long-tail)
`--convert` roda `convert-enunciado.sh` (tex/org → md canônico). É **best-effort**: o que não
converte limpo entra no `migration-report.tsv` como `convert-failed:<fmt>(curar)` para
**curadoria manual**. Esperado em `problemas-apc` (79 `.tex`) e nos `.org`. Os **exemplos** são
sempre injetados dos testes (`tests/.../sample*`), então ficam visíveis mesmo no legado.

## Segurança / idempotência
- DRY-RUN é o default; `--write` opera num **clone temp** (NFS intacto); reexecutar é seguro.
- `--push` cria usuário/repo no Gitea (lazy) e faz `push -f` do clone migrado (história + commit
  de migração). Tokens só server-side (600), nunca no `.git/config` (askpass do `git-broker.sh`).
- O único passo "de mão única" é repointar o `origin` — feito **por último** e **reversível**.
