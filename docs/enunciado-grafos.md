# Grafos no enunciado (`.graph`)

Quando o enunciado precisa **desenhar um grafo** (uma rede de cidades, uma árvore, um autômato),
você escreve o grafo em **[graphviz DOT](https://graphviz.org/doc/info/lang.html)** dentro de um bloco
de código com a classe `.graph`. O renderizador único (`render-statement.sh`) roda o `dot` e troca o
bloco por um **SVG inline** — no "Pré-visualizar" do editor, no HTML que o aluno lê e na validação, do
mesmo jeito (regra "Um renderizador só"). Você mantém a **fonte DOT** no `docs/enunciado.md` (editável),
não uma imagem colada.

## Sintaxe

    ```{ .graph .center caption="Estradas asfaltadas de Nlogônia" }
    graph Nlogônia {
      NlogTiba -- NlogNópolis;
      NlogSília -- NlogRizonte;
      NlogSília -- Nlogânia;
      Nlogânia -- NlogPrata;
    }
    ```

- **`.graph`** (obrigatória) — marca o bloco como grafo. Sem ela é um bloco de código normal.
- **`.center`** (opcional) — centraliza a figura.
- **`caption="…"`** (opcional) — vira o rótulo acessível (`aria-label`) da figura — não aparece
  visível, é para leitor de tela / `alt`.
- **`prog="neato"`** (opcional) — troca o programa de layout do graphviz (`dot` é o default; há também
  `neato`, `fdp`, `circo`, `twopi`).

O corpo do bloco é DOT puro: `graph` (não-direcionado, arestas `--`) ou `digraph` (direcionado, `->`),
com os recursos usuais — `rankdir`, `label="…"` em arestas, `color`, `style`, `dir`, etc. Nomes de nó
com acento (`Nlogônia`) funcionam (UTF-8).

## Exemplos que já usam

- `moj-problems#grafo-ajude-joao` — grafo não-direcionado simples (componentes conexas).
- `moj-problems#grafo-chp` — arestas com peso (`label`) + uma aresta direcionada afilada
  (`dir=forward,style=tapered`), `rankdir="LR"`.
- `moj-problems#grafo-nlogonia-conexoes` — `digraph` com arestas coloridas / `dir=both`.
- `moj-problems#grafo-nucleos-cidades` — grafo com `size="8,5"`.

## Como testar

Use o **"Pré-visualizar"** do editor web (é o mesmo render do servido). Na linha de comando:

```sh
bash mojtools/render-statement.sh docs/enunciado.md md "" "Título" > /tmp/preview.html
```

e abra o `/tmp/preview.html`. Você deve ver a figura (um `<figure class="moj-graph …"><svg …>`), não o
texto DOT dentro de um `<pre>`.

## Requisitos e degradação

- O `dot` (pacote **graphviz**) precisa estar onde o `render-statement.sh` roda — ou seja, na imagem
  do servidor (`cdmoj/deploy/Containerfile` instala `graphviz`; há asserção de build). Nos juízes não
  precisa: eles não renderizam enunciado.
- Se o `dot` faltar **ou** o DOT for inválido, o filtro (`graphviz.lua`) **deixa o bloco como código**
  (não quebra o enunciado inteiro) e escreve um aviso no stderr. Então um DOT com erro de sintaxe
  aparece como texto — conserte o DOT e pré-visualize de novo.

## Detalhe técnico

O mecanismo é o lua-filter `mojtools/graphviz.lua`, ligado na chamada do `pandoc` dentro do
`render-statement.sh` (`--lua-filter`). Ele gera o SVG **inline** (sem arquivo de imagem no pacote,
logo **não** entra no `tl-checksum` e não dispara recalibração). Isto substitui o mecanismo antigo do
repo `moj-problems` (um `.pandocfilters/graphviz.py` com pygraphviz, chamado pelo Makefile), que a
migração para o formato canônico havia deixado para trás.
