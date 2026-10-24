-- Passive tree description lines in the player's language (no client API, tested by treetext_test.lua).
-- The data files (treedata/nodes.lua) and the class texts of the tree window hold a description as short lines
-- ({"A hit taken from a creature reflects 20% of what", "landed ..."}): a translation is a whole paragraph, so
-- TreeText.lines joins the lines with a space, asks tr() for the paragraph (pt_br.lua, "Passive tree descriptions") and,
-- when it has a translation, breaks it again into lines as wide as the longest English one. Without a translation the
-- lines come back unchanged (English).
--   TreeText.join(lines)         the paragraph: the lines joined with one space
--   TreeText.wrap(text, width)   the words of the text in lines of at most `width` bytes (a longer word keeps its own line)
--   TreeText.lines(lines)        the lines to show
local function tr(s, ...) local g = rawget(_G, 'tr') if g then return g(s, ...) end if select('#', ...) > 0 then return string.format(s, ...) end return s end -- i18n (client_chaos_locale)

TreeText = {}
local T = TreeText

function T.join(lines)
  return table.concat(lines or {}, ' ')
end

function T.wrap(text, width)
  local out, line = {}, ''
  for word in tostring(text or ''):gmatch('%S+') do
    if line == '' then
      line = word
    elseif #line + 1 + #word <= width then
      line = line .. ' ' .. word
    else
      out[#out + 1] = line
      line = word
    end
  end
  if line ~= '' then out[#out + 1] = line end
  return out
end

function T.lines(lines)
  if type(lines) ~= 'table' or #lines == 0 then return lines or {} end
  local text = T.join(lines)
  local shown = tr(text)
  if shown == text or type(shown) ~= 'string' then return lines end
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, #l) end
  return T.wrap(shown, width)
end

return T
