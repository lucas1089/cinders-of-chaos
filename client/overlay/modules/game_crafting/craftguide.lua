-- Crafting Guide window (owner request 2026-11-03): the Guide button of the crafting bench opens it. Orbs tab: the basics,
-- a safe first plan, every orb of the bench with what it does (the server's text), when to use it and how risky it is,
-- and how many you carry. Gems tab: how gems work and every gem's bonus per slot group and quality, from the server's
-- gemguide message (ChaosGems.guide()). Texts: craftguideview.lua. crafting.lua keeps `info`, `state` and `gemGuide`.
local V = CraftGuideView
local guideWindow
local guideTab = 'orbs'

local function alive(w)
  return w and not w:isDestroyed()
end

local function head(list, text)
  local w = g_ui.createWidget('CraftGuideHead', list)
  w:setText(text)
end

local function para(list, text, color)
  local w = g_ui.createWidget('CraftGuideText', list)
  w:setText(text)
  if color then w:setColor(color) end
end

local function line(list, clientId, name, note, noteColor)
  local w = g_ui.createWidget('CraftGuideLine', list)
  w.icon:setItemId(tonumber(clientId) or 0)
  w.name:setText(name)
  w.note:setText(note or '')
  if noteColor then w.note:setColor(noteColor) end
end

local function fillOrbs(list)
  head(list, tr('How crafting works'))
  for _, b in ipairs(V.basics(tr)) do
    para(list, b[1] .. ': ' .. b[2])
  end
  head(list, tr('A safe first plan'))
  for _, step in ipairs(V.plan(tr)) do
    para(list, step)
  end
  head(list, tr('Every orb'))
  local counts = guideCounts and guideCounts() or {}
  local orbs = guideOrbs and guideOrbs() or {}
  if #orbs == 0 then
    para(list, tr('Open the crafting bench once to load the list of orbs.'))
  end
  for _, orb in ipairs(orbs) do
    local risk = V.RISK[orb.key]
    line(list, orb.clientId, orb.name or orb.key, tr('You have %d.', tonumber(counts[orb.key]) or 0) .. '  '
      .. V.riskText(risk, tr), V.RISK_COLOR[risk])
    if orb.text and orb.text ~= '' then para(list, tr('What it does: %s', orb.text)) end
    local advice = V.advice(orb.key, tr)
    if advice ~= '' then para(list, tr('When to use it: %s', advice), '#b9c7d6') end
  end
end

local function fillGems(list)
  local guide = guideGems and guideGems() or nil
  for _, b in ipairs(V.gemBasics(guide, tr)) do
    head(list, b[1])
    para(list, b[2])
  end
  head(list, tr('Every gem, from the worst quality to the best'))
  local rows = V.gemRows(guide, tr)
  if #rows == 0 then
    para(list, tr('Open the crafting bench once to load the gem table.'))
  end
  for _, row in ipairs(rows) do
    line(list, row.look, row.name, '', nil)
    for _, g in ipairs(row.groups) do
      local cap = g.cap ~= '' and ('  ' .. tr('(limit %s)', g.cap)) or ''
      para(list, g.label .. ': ' .. g.text .. cap)
    end
  end
end

local function fill()
  if not alive(guideWindow) then return end
  guideWindow.orbsTab:setChecked(guideTab == 'orbs')
  guideWindow.gemsTab:setChecked(guideTab == 'gems')
  local list = guideWindow.list
  list:destroyChildren()
  local ok, err = pcall(guideTab == 'gems' and fillGems or fillOrbs, list)
  if not ok then g_logger.warning('[crafting] guide: ' .. tostring(err)) end
  if guideWindow.scroll then guideWindow.scroll:setValue(0) end
end

function setGuideTab(tab)
  guideTab = tab == 'gems' and 'gems' or 'orbs'
  fill()
end

function showGuide(tab)
  if not alive(guideWindow) then
    guideWindow = g_ui.displayUI('craftguide')
  end
  if tab then guideTab = tab end
  fill()
  guideWindow:show()
  guideWindow:raise()
  guideWindow:focus()
end

function hideGuide()
  if alive(guideWindow) then guideWindow:hide() end
end

-- crafting.lua: new data arrived; redraw an open guide
function refreshGuide()
  if alive(guideWindow) and guideWindow:isVisible() then fill() end
end

function destroyGuide()
  if alive(guideWindow) then guideWindow:destroy() end
  guideWindow = nil
end
