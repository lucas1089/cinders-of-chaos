-- "How it works" (client/MANIFEST.md): ONE shared card that explains a feature in very plain words: who it is for, the
-- monster levels, what drops, what a death costs, how often. The texts are generated from the server configs
-- (howitworks_data.lua, server/tools/gen_howitworks_data.lua); howcore.lua picks the cards. No opcode.
-- API (modules.game_howitworks), every call is safe to make when the module is missing (guard with the module table):
--   attach(window, key [, moduleName])  a "?" button in the top right of a feature window; key = card key, or nil to use
--                                       the card whose `window` is moduleName
--   attachGoal(row, goalKey)            a "?" button in a Next Goals row (only when a card answers that goal)
--   show(key) / showForUnlock(unlockKey) / showForGoal(goalKey)   open the card; true when there is one
--   hasUnlock(unlockKey) / hasGoal(goalKey)                       is there a card for it
--   hide()

local H = HowCore
local window
local LABELS -- filled in init: row id -> heading (literal tr() calls, checked by tools/ci/check_locales.py)

local function lang()
  local l = rawget(_G, 'ChaosLocale')
  return l and l.get and l.get() or 'en'
end

local function convert(s)
  local core = rawget(_G, 'ChaosLocaleCore')
  return core and core.toCp1252 and core.toCp1252(s) or s
end

local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function headings()
  return {
    what = tr('What it is'),
    who = tr('Who is it for'),
    levels = tr('Monster levels'),
    drops = tr('What drops'),
    death = tr('If you die'),
    often = tr('How often'),
  }
end

-- ---------------------------------------------------------------- the card window
function hide()
  if alive(window) then window:hide() end
end

local function draw(card)
  window:setText(tr('How it works') .. ': ' .. H.title(card, lang(), convert))
  local list = window:getChildById('list')
  list:destroyChildren()
  LABELS = headings()
  for _, r in ipairs(H.rows(card, lang(), convert)) do
    local head = g_ui.createWidget('HowRowHead', list)
    head:setText(LABELS[r.id] or r.id)
    local text = g_ui.createWidget('HowRowText', list)
    text:setText(r.text)
  end
  window:show()
  window:raise()
  window:focus()
end

local function showCard(card)
  if not card or not alive(window) then return false end
  local ok, err = pcall(draw, card)
  if not ok then g_logger.warning('[howitworks] ' .. tostring(err)) end
  return ok
end

function show(key) return showCard(H.find(HowData, key)) end
function showForUnlock(key) return showCard(H.forUnlock(HowData, key)) end
function showForGoal(key) return showCard(H.forGoal(HowData, key)) end
function hasUnlock(key) return H.forUnlock(HowData, key) ~= nil end
function hasGoal(key) return H.forGoal(HowData, key) ~= nil end

-- ---------------------------------------------------------------- the "?" buttons
local function makeButton(parent, card)
  local b = g_ui.createWidget('HowButton', parent)
  b:setText('?')
  b:setTooltip(tr('How it works: who it is for, what drops, what a death costs.'))
  local key = card.key
  b.onClick = function() show(key) end
  return b
end

function attach(target, key, moduleName)
  if not alive(target) then return nil end
  local card = key and H.find(HowData, key) or H.forWindow(HowData, moduleName)
  if not card then return nil end
  if alive(target.howButton) then target.howButton:destroy() end
  local b = makeButton(target, card)
  b:addAnchor(AnchorTop, 'parent', AnchorTop)
  b:addAnchor(AnchorRight, 'parent', AnchorRight)
  b:setMarginTop(7)
  b:setMarginRight(22)
  target.howButton = b
  return b
end

function attachGoal(row, goalKey)
  local card = H.forGoal(HowData, goalKey)
  if not card or not alive(row) then return nil end
  local b = makeButton(row, card)
  b:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  b:addAnchor(AnchorRight, 'parent', AnchorRight)
  b:setMarginBottom(5)
  b:setMarginRight(6)
  return b
end

-- ---------------------------------------------------------------- module
function init()
  local ok, ui = pcall(g_ui.displayUI, 'howitworks')
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[howitworks] window not loaded: ' .. tostring(ui))
  end
end

function terminate()
  if alive(window) then window:destroy() end
  window = nil
end
