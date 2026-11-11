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
-- First open (owner request 2026-11-03): attach() also watches the window; the first time a character sees it, the card
-- opens by itself (once per character and card, settings node chaos_howitworks_seen). The card's check box turns this
-- off for every character (setting chaos_howitworks_auto, on by default).

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

-- ---------------------------------------------------------------- first open
local SEEN_NODE, AUTO_KEY = 'chaos_howitworks_seen', 'chaos_howitworks_auto'

function autoOn()
  local st = rawget(_G, 'g_settings')
  if not st then return false end
  if st.exists and not st.exists(AUTO_KEY) then return true end
  return st.getBoolean(AUTO_KEY) and true or false
end

function setAuto(on)
  local st = rawget(_G, 'g_settings')
  if st then st.set(AUTO_KEY, on and true or false) end
end

-- true the first time this character opens the card's window (and remembers it)
local function firstOpen(key)
  local st = rawget(_G, 'g_settings')
  if not st or not autoOn() then return false end
  local seen = st.getNode(SEEN_NODE)
  if type(seen) ~= 'table' then seen = {} end
  local game = rawget(_G, 'g_game')
  local name = game and game.getCharacterName and game.getCharacterName() or nil
  if not H.firstOpen(seen, H.charKey(name), key) then return false end
  st.setNode(SEEN_NODE, seen)
  return true
end

local function visible(w)
  local ok, v = pcall(function() return w:isVisible() end)
  return ok and v
end

-- the card opens a moment after the window, so it lands on top of it
local function watch(target, key)
  local function check()
    if alive(target) and visible(target) and firstOpen(key) then
      local later = rawget(_G, 'scheduleEvent')
      if later then later(function() show(key) end, 250) else show(key) end
    end
  end
  if not target.howWatched and rawget(_G, 'connect') then
    target.howWatched = true
    connect(target, { onVisibilityChange = function(_, shown) if shown then check() end end })
  end
  check()
end

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
  -- the title bar corner of the window, not of its content: the anchor uses the padding rect (HowCore.buttonMargins)
  local function pad(fn)
    local ok, v = pcall(function() return target[fn](target) end)
    return ok and v or 0
  end
  local top, right = H.buttonMargins(pad('getPaddingTop'), pad('getPaddingRight'))
  b:setMarginTop(top)
  b:setMarginRight(right)
  target.howButton = b
  watch(target, card.key)
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
    local box = window:getChildById('autoBox')
    if box then
      box:setChecked(autoOn())
      box.onCheckChange = function(_, checked) setAuto(checked) end
    end
  else
    g_logger.warning('[howitworks] window not loaded: ' .. tostring(ui))
  end
end

function terminate()
  if alive(window) then window:destroy() end
  window = nil
end
