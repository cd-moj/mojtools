-- graphviz.lua — lua-filter do pandoc: converte blocos ```{.graph} (fonte
-- graphviz DOT) em SVG inline. É o que restaura o mecanismo que o repo antigo
-- tinha via .pandocfilters/graphviz.py (pygraphviz), agora dentro do
-- renderizador único (render-statement.sh) — ver docs/enunciado-grafos.md.
--
-- Precisa só do binário `dot` (graphviz) no PATH (nem pygraphviz nem
-- pandocfilters). Não escreve arquivo de cache (SVG vai inline, não polui o
-- pacote nem o tl-checksum). Se o `dot` faltar ou o DOT for inválido, DEIXA o
-- bloco como está (código) — degrada, nunca quebra o render.
--
-- Sintaxe do bloco (no docs/enunciado.md):
--   ```{ .graph .center caption="Legenda" }
--   graph G { a -- b; b -- c; }
--   ```
-- Atributos: `.center` centraliza; `caption="…"` vira rótulo acessível
-- (aria-label, invisível — igual ao comportamento antigo); `prog="neato"`
-- troca o layout (default `dot`).
function CodeBlock(el)
  if not el.classes:includes("graph") then return nil end
  local prog = el.attributes["prog"] or "dot"
  local ok, svg = pcall(pandoc.pipe, prog, {"-Tsvg"}, el.text)
  if not ok then
    io.stderr:write("graphviz.lua: '" .. prog .. "' falhou; bloco .graph deixado como codigo\n")
    return nil
  end
  svg = svg:gsub("^.-(<svg)", "%1")  -- remove prolog XML/DOCTYPE/comentarios ate <svg
  local cls = "moj-graph"
  if el.classes:includes("center") then cls = cls .. " center" end
  local cap = el.attributes["caption"]
  local aria = ""
  if cap and cap ~= "" then
    aria = ' role="img" aria-label="' .. cap:gsub('&', '&amp;'):gsub('"', '&quot;') .. '"'
  end
  return pandoc.RawBlock("html", '<figure class="' .. cls .. '"' .. aria .. '>' .. svg .. '</figure>')
end
