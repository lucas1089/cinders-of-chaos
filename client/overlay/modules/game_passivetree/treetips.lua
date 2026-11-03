-- Node tooltip with the stat explanations behind Alt (owner request 2026-11-03).
-- A node tooltip shows its name, bonuses, class lines and requirements. The lines that explain what each stat does
-- (statinfo.lua) appear only while Alt is held; without Alt a last line says so. The joining is the shared
-- ChaosAltHelp.lines (client_chaos_theme althelp.lua, O372); this file gives it the tree's own hint. Pure logic, no
-- engine calls (treetips_test.lua); tr is passed in so the test needs no locale.
TreeTips = {}

-- texts: the plain lines; extra: the explanation lines (may be empty); altDown: Alt held now
-- returns the lines to show
function TreeTips.lines(texts, extra, altDown, tr)
  return ChaosAltHelp.lines(texts, extra, altDown, tr, tr('Hold Alt for what each bonus does.'))
end

return TreeTips
