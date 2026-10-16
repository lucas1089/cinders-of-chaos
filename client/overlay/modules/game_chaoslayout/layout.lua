-- game_chaoslayout: the window layout of each character (client/MANIFEST.md "Window layout per character").
-- The base client restores miniwindows from a settings node no module ever writes (and skips it past 50 entries), so
-- the layout never persisted. This module keeps, per character (world/name, client settings node chaos_layout):
-- * the side panel miniwindows (Skills, Battle, VIP, Party, our Chaos panels...): panel and side, order, height,
--   collapsed, open or closed, locked; and how many side panels there were. Container windows are left out (their
--   ids are slots, not containers);
-- * the position (and the size of a resizable one) of the big Chaos windows, clamped to the game window.
-- Restored after login once the panels exist; a window created later is placed when it appears. Saved within a
-- second of a change (a 1 s check while online) and never before this character's layout was restored (a fresh
-- login's defaults never replace it). Logout and death need no save of their own: the last change is on disk.
ChaosLayout = ChaosLayout or {}
local M = ChaosLayout
local L = ChaosLayoutLogic

M.BIG_WINDOWS = { 'spellbookWindow', 'cosmeticsWindow', 'chaosInfoWindow', 'leaderboardWindow', 'amountWindow',
  'pouchesWindow', 'lootFilterWindow', 'autoSellerWindow' }
local TICK = 1000
local SIDE_BUTTONS = { skillWindow = 'skillsWidget', battleWindow = 'battleListWidget', vipWindow = 'vipWidget',
  spellListWidget = 'spellListWidget' }

local st = L.newSession()
local saved = nil       -- this character's layout (as restored, then as saved)
local pending = {}      -- saved miniwindows not found at the restore: placed when they appear
local big = {}          -- [id] = { widget, restored }
local tickEvent, startEvent = nil, nil

local function gameRoot()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

local function charKey()
  return L.key(g_game.getWorldName and g_game.getWorldName() or nil, g_game.getCharacterName())
end

local function isMini(w)
  return w and w.minimize ~= nil and w.maximize ~= nil and w.isResizeable ~= nil
end

-- the side panels in order: { id, side, persistent, widget }
local function sidePanels()
  local out = {}
  local r = gameRoot()
  if not r then return out end
  for _, pair in ipairs({ { 'gameLeftPanels', 'left' }, { 'gameRightPanels', 'right' } }) do
    local holder = r:getChildById(pair[1])
    for _, c in ipairs(holder and holder:getChildren() or {}) do
      if c:getClassName() == 'UIMiniWindowContainer' then
        local id = c:getId()
        out[#out + 1] = { id = id, side = pair[2], widget = c, persistent = not tostring(id):lower():find('reserv') }
      end
    end
  end
  return out
end

local function snapshotNow()
  local containers = {}
  for _, p in ipairs(sidePanels()) do
    local windows = {}
    for _, w in ipairs(p.widget:getChildren()) do
      if isMini(w) then
        local minimized = w:isOn()
        local old = saved and saved.mini and saved.mini[w:getId()]
        windows[#windows + 1] = { id = w:getId(), visible = w:isExplicitlyVisible(), minimized = minimized,
          locked = w.isLocked and w:isLocked() or false,
          height = minimized and (old and old.height or nil) or w:getHeight() }
      end
    end
    containers[#containers + 1] = { id = p.id, side = p.side, persistent = p.persistent, windows = windows }
  end
  local snap = L.snapshot(containers)
  snap.windows = {}
  for id, b in pairs(big) do
    if b.restored and b.rect then snap.windows[id] = b.rect end
  end
  return snap
end

local function write(layout)
  local key = charKey()
  if not L.canSave(st, key) then return end
  if not L.changed(st, layout) then return end
  local node = g_settings.getNode(L.NODE) or {}
  node[key] = layout
  g_settings.setNode(L.NODE, node)
  if g_settings.save then g_settings.save() end
  saved = layout
end

-- ---------------------------------------------------------------- restore
local function windowsById()
  local map = {}
  for _, p in ipairs(sidePanels()) do
    for _, w in ipairs(p.widget:getChildren()) do
      if isMini(w) then map[w:getId()] = w end
    end
  end
  local ui = g_ui.getRootWidget()
  for _, w in ipairs(ui and ui:getChildren() or {}) do -- a miniwindow dragged out of the panels
    if isMini(w) then map[w:getId()] = w end
  end
  return map
end

local function applyOne(w, target, index, e)
  if w:getParent() ~= target then
    local old = w:getParent()
    if old then old:removeChild(w) end
    target:insertChild(math.min(index, target:getChildCount() + 1), w)
  else
    target:moveChildToIndex(w, math.min(index, target:getChildCount()))
  end
  w.miniIndex = index
  if e.minimized then
    if not w:isOn() then pcall(w.minimize, w, true) end
  else
    if w:isOn() then pcall(w.maximize, w, true) end
    if e.height and w:isResizeable() then w:setHeight(e.height) end
  end
  if e.closed then
    if w:isExplicitlyVisible() then pcall(w.close, w) end
  elseif not w:isExplicitlyVisible() then
    pcall(w.open, w)
    local button = SIDE_BUTTONS[w:getId()]
    if button and modules.game_sidebuttons and modules.game_sidebuttons.setButtonVisible then
      pcall(modules.game_sidebuttons.setButtonVisible, button, true)
    end
  end
  if w.lock and w.unlock and w.isLocked then
    if e.locked and not w:isLocked() then pcall(w.lock, w, true)
    elseif not e.locked and w:isLocked() then pcall(w.unlock, w) end
  end
end

local function panelsMaps()
  local existing, first, byId = {}, {}, {}
  for _, p in ipairs(sidePanels()) do
    if p.persistent then
      existing[p.id] = p.side
      first[p.side] = first[p.side] or p.id
      byId[p.id] = p.widget
    end
  end
  return existing, first, byId
end

local function restoreMini()
  pending = {}
  if not saved or not saved.mini then return end
  local gi = modules.game_interface
  -- as many side panels as the character had (never fewer: removing a panel is the player's choice)
  local counts = saved.panels or {}
  for _, side in ipairs({ 'left', 'right' }) do
    local have = 0
    for _, p in ipairs(sidePanels()) do if p.side == side and p.persistent then have = have + 1 end end
    local add = side == 'left' and gi.addLeftPanel or gi.addRightPanel
    for _ = have + 1, math.min(4, tonumber(counts[side]) or 0) do
      if add then pcall(add) end
    end
  end
  local existing, first, byId = panelsMaps()
  local windows = windowsById()
  for panelId, list in pairs(L.placement(saved, existing, first)) do
    local target = byId[panelId]
    for i, e in ipairs(list) do
      local w = windows[e.id]
      if w and target then applyOne(w, target, i, e) else pending[e.id] = { panel = panelId, index = i, entry = e } end
    end
    if target and target.fitAll then pcall(target.fitAll, target) end
  end
end

local function placeLate()
  if not next(pending) then return end
  local _, _, byId = panelsMaps()
  local windows = windowsById()
  for id, p in pairs(pending) do
    local w, target = windows[id], byId[p.panel]
    if w and target then
      applyOne(w, target, p.index, p.entry)
      pending[id] = nil
    end
  end
end

-- big windows: the saved position (and size when it can be resized), clamped to the game window
local function resizable(w)
  for _, c in ipairs(w:getChildren()) do
    if c:getClassName() == 'UIResizeBorder' then return true end
  end
  return false
end

local function restoreBig(id, w)
  local b = big[id]
  local rect = saved and saved.windows and saved.windows[id]
  local ui = g_ui.getRootWidget()
  if rect and ui then
    local area = { x = 0, y = 0, width = ui:getWidth(), height = ui:getHeight() }
    local size = w:getSize()
    local want = { x = rect.x, y = rect.y, width = resizable(w) and rect.width or size.width,
      height = resizable(w) and rect.height or size.height }
    local c = L.clampRect(want, area, { width = math.min(size.width, 200), height = math.min(size.height, 120) })
    w:breakAnchors()
    if resizable(w) then w:setSize({ width = c.width, height = c.height }) end
    w:setPosition({ x = c.x, y = c.y })
  end
  b.restored = true
end

local function watchBig()
  local ui = g_ui.getRootWidget()
  if not ui then return end
  for _, id in ipairs(M.BIG_WINDOWS) do
    local w = ui:getChildById(id)
    local b = big[id]
    if w and (not b or b.widget ~= w) then
      b = { widget = w, restored = false }
      big[id] = b
      connect(w, { onVisibilityChange = function(self, visible)
        if visible and st.ready and not big[id].restored then restoreBig(id, self) end
      end })
    end
    if b and w and w:isVisible() and st.ready then
      if not b.restored then restoreBig(id, w) end
      local r = w:getRect()
      b.rect = { x = r.x, y = r.y, width = r.width, height = r.height }
    end
  end
end

-- ---------------------------------------------------------------- lifecycle
local function tick()
  tickEvent = nil
  if not g_game.isOnline() then return end
  if st.ready then
    placeLate()
    watchBig()
    write(L.merge(saved, snapshotNow()))
  end
  tickEvent = scheduleEvent(tick, TICK)
end

local function onGameStart()
  L.begin(st)
  saved, pending = nil, {}
  for _, b in pairs(big) do b.restored, b.rect = false, nil end
  if startEvent then removeEvent(startEvent) end
  -- after game_interface and the panel modules have set up their windows
  startEvent = scheduleEvent(function()
    startEvent = nil
    if not g_game.isOnline() then return end
    local key = charKey()
    local node = g_settings.getNode(L.NODE) or {}
    saved = type(node[key]) == 'table' and node[key] or nil
    pcall(restoreMini)
    L.restored(st, key, saved)
    watchBig()
    if not tickEvent then tickEvent = scheduleEvent(tick, TICK) end
  end, 800)
end

local function onGameEnd()
  -- the last change is already written (tick); a logout's window closing must not be saved
  L.begin(st)
  if startEvent then removeEvent(startEvent) startEvent = nil end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
end

function M.init()
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()
end
