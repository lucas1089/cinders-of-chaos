-- Node tooltip with the stat explanations behind Alt (owner request 2026-11-03).
-- A node tooltip shows its name, bonuses, class lines and requirements. The lines that explain what each stat does
-- (statinfo.lua) appear only while Alt is held; without Alt a last line says so. Pure logic, no engine calls
-- (treetips_test.lua); tr is passed in so the test needs no locale.
TreeTips = {}

-- texts: the plain lines; extra: the explanation lines (may be empty); altDown: Alt held now
-- returns the lines to show
function TreeTips.lines(texts, extra, altDown, tr)
  local out = {}
  for _, line in ipairs(texts or {}) do
    out[#out + 1] = line
  end
  if extra and #extra > 0 then
    if altDown then
      for _, line in ipairs(extra) do
        out[#out + 1] = line
      end
    else
      out[#out + 1] = tr('Hold Alt for what each bonus does.')
    end
  end
  return out
end

return TreeTips
