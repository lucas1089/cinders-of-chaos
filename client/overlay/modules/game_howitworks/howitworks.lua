-- "How it works" (client/MANIFEST.md): ONE shared card that explains a feature in very plain words: who it is for, the
-- monster levels, what drops, what a death costs, how often. The texts are generated from the server configs
-- (howitworks_data.lua, server/tools/gen_howitworks_data.lua); howcore.lua picks the cards. No opcode.
-- API (modules.game_howitworks), every call is safe to make when the module is missing (guard with the module table):
--   attach(window, key [, moduleName])  a "?" button in the top right of a feature window; key = card key, or nil to use
--                                       the card whose `window` is moduleName (a window of many pages attaches the card
--                                       of the page shown, O732 follow-up)
--   detach(window)                      no "?" button and no first-open card (a page with no card)
--   attachGoal(row, goalKey)            a "?" button in a Next Goals row (only when a card answers that goal)
--   show(key) / showForUnlock(unlockKey) / showForGoal(goalKey)   open the card; true when there is one
--   hasUnlock(unlockKey) / hasGoal(goalKey)                       is there a card for it
--   hide()
--   reposition()                        the card left of the side dock again (game_chaosdock calls it when it widens)
-- First open (owner request 2026-11-03): attach() also watches the window; the first time a character sees it, the card
-- opens by itself (once per character and card, settings node chaos_howitworks_seen). The card's check box turns this
-- off for every character (setting chaos_howitworks_auto, on by default). A window with `howQuiet` set opened by itself (O761: the
-- Daily Reward at a first login): no card then, it comes the first time the player opens it.

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

-- the card keeps left of the side dock (game_chaosdock, O732) while the dock is open; centred otherwise
local placed = false
local naturalWidth = nil -- the card's own width (it narrows to the room left of a wide dock)
local function place()
  if not alive(window) then return end
  local dockModule = rawget(_G, 'modules') and modules.game_chaosdock
  local dock = (dockModule and rawget(dockModule, 'ChaosDock')) or rawget(_G, 'ChaosDock')
  local ok, cover = pcall(function() return dock and dock.coverRight and dock.coverRight() or 0 end)
  cover = ok and tonumber(cover) or 0
  if cover <= 0 and not placed then return end
  local parent = window:getParent()
  if not parent then return end
  local pr = parent:getRect()
  naturalWidth = naturalWidth or window:getWidth()
  local x, width = H.cardFit(pr.x, pr.width, naturalWidth, cover)
  local y = math.max(pr.y, pr.y + math.floor((pr.height - window:getHeight()) / 2))
  window:breakAnchors()
  if window:getWidth() ~= width then window:setWidth(width) end
  window:setPosition({ x = x, y = y })
  placed = cover > 0
end

-- the dock calls this when the width it covers changes (it widens for a window after the card opened)
function reposition()
  if alive(window) and window:isVisible() then pcall(place) end
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
  pcall(place)
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

-- V41 / V42 (seen in a client): the card came back after every restart. The seen marks and the check box lived only in
-- the settings in memory, written to disk at a clean exit; a client that is killed, crashes or loses its display never
-- wrote them. Both are on disk at once now (g_settings.save, as game_partyframes and game_dpsmeter do).
local function saveNow(st)
  if st and st.save then pcall(st.save) end
end

function setAuto(on)
  local st = rawget(_G, 'g_settings')
  if st then
    st.set(AUTO_KEY, on and true or false)
    saveNow(st)
  end
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
  saveNow(st)
  return true
end

local function visible(w)
  local ok, v = pcall(function() return w:isVisible() end)
  return ok and v
end

-- the card opens a moment after the window, so it lands on top of it
-- the key is read when the window shows: a window of many pages changes it with the page (target.howKey)
local function watch(target)
  local function check()
    local key = target.howKey
    -- howQuiet: the window opened by itself (the Daily Reward at login, O761): no card now, it stays due for the next opening
    if key and not target.howQuiet and alive(target) and visible(target) and firstOpen(key) then
      local later = rawget(_G, 'scheduleEvent')
      if later then later(function() show(key) end, 250) else show(key) end
    end
  end
  if not target.howWatched and rawget(_G, 'connect') then
    target.howWatched = true
    connect(target, { onVisibilityChange = function(_, shown) if shown then check() end end })
  end
  -- the look at attach time waits one event: a window loaded visible and hidden by its module in the same call (the
  -- passive tree builds itself at login and hides at the end) was never opened by the player, so no card then (V34)
  local later = rawget(_G, 'scheduleEvent')
  if later then later(check, 0) else check() end
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
  target.howKey = card.key
  watch(target)
  return b
end

function detach(target)
  if not alive(target) then return end
  if alive(target.howButton) then target.howButton:destroy() end
  target.howButton = nil
  target.howKey = nil
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
