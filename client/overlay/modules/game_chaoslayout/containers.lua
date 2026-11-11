-- game_chaoslayout, the open containers (O412; client/MANIFEST.md "Window layout per character"; rules in
-- containers_logic.lua, tested by containers_test.lua). A container window has a server container id, new at every
-- login, so it is remembered by where its item sits: the inventory slot, then the index in each parent container
-- (a key, "3_2854/1_1987"). The key of a window is learnt when the player opens it: g_game.open and g_game.use are
-- wrapped to note the position of the item opened, and Container.onOpen gives the window that key.
-- At login (option "Remember open backpacks", on by default) the saved containers open again one by one, each after
-- its parent (g_game.open on the inventory item, then on the item inside the parent; a short gap between two opens),
-- then go to their panel, order, height and scroll. A container that is gone is skipped. On a phone game_mobilebag
-- keeps sizing the windows (its cells fill the panel): the height is not set there. A container the side panels have no
-- room for still opens (base patch 0191, O485): the others shrink, none closes; see ChaosPanelRoom (panelroom_logic.lua).
--   ChaosLayout.Containers.snapshot()            the open containers as the layout saves them
--   ChaosLayout.Containers.restore(list, done)   reopen a saved list
--   ChaosLayout.Containers.openPath(steps, at)   open the containers of steps (Find my item) and flash slot `at`
ChaosLayout = ChaosLayout or {}
local M = ChaosLayout
local C = ChaosContainerLogic
local K = {}
M.Containers = K

local keyById = {}    -- container id -> key
local pending = {}    -- opens asked for, not answered yet: { { key, id, cid, at } }
local origOpen, origUse, origParent, wrapOpen, wrapUse, wrapParent
local events = {}     -- scheduled events of a restore or an openPath
local run = 0         -- the restore / openPath now running (a newer one stops the older)
K.busy = false        -- a restore runs: the layout keeps the saved list meanwhile

local function nowMs() return g_clock and g_clock.millis and g_clock.millis() or 0 end
local function later(fn, ms)
  local e
  e = scheduleEvent(function()
    for i, x in ipairs(events) do if x == e then table.remove(events, i) break end end
    fn()
  end, ms)
  events[#events + 1] = e
end
local function stopEvents()
  for _, e in ipairs(events) do removeEvent(e) end
  events = {}
end

local function isMobile() return g_app and g_app.isMobile and g_app.isMobile() or false end

function K.enabled()
  local cs = modules.client_settings
  local v = nil
  if cs and cs.getOption then
    local ok, value = pcall(cs.getOption, 'rememberBackpacks')
    if ok then v = value end
  end
  return C.enabled(v)
end

-- ---------------------------------------------------------------- learning the keys
local function isContainerItem(thing)
  if not thing or not thing.isItem then return false end
  local ok, item = pcall(thing.isItem, thing)
  if not ok or not item then return false end
  local okC, c = pcall(thing.isContainer, thing)
  return okC and c == true
end

local function note(thing, cid)
  if not isContainerItem(thing) then return end
  local key = C.fromPosition(thing:getPosition(), thing:getId(), keyById)
  if key then pending[#pending + 1] = { key = key, id = thing:getId(), cid = cid, at = nowMs() } end
end

local function hook()
  if origOpen then return end
  origOpen, origUse, origParent = g_game.open, g_game.use, g_game.openParent
  wrapOpen = function(item, previous, ...)
    local cid = origOpen(item, previous, ...)
    pcall(note, item, tonumber(cid))
    return cid
  end
  wrapUse = function(thing, ...)
    pcall(note, thing, nil)
    return origUse(thing, ...)
  end
  wrapParent = function(container, ...)
    local key = container and keyById[container:getId()]
    local parent = key and C.parentKey(key)
    if parent then pending[#pending + 1] = { key = parent, cid = container:getId(), at = nowMs() } end
    return origParent(container, ...)
  end
  g_game.open, g_game.use, g_game.openParent = wrapOpen, wrapUse, wrapParent
end

local function unhook()
  if not origOpen then return end
  -- another module may have wrapped them after us: only ours are put back
  if g_game.open == wrapOpen then g_game.open = origOpen end
  if g_game.use == wrapUse then g_game.use = origUse end
  if g_game.openParent == wrapParent then g_game.openParent = origParent end
  origOpen, origUse, origParent = nil, nil, nil
end

-- the slot container a window with no known key may be (a backpack the client or the server opened by itself)
local function slotKey(container)
  local player = g_game.getLocalPlayer()
  local item = container:getContainerItem()
  if not player or not item or container:hasParent() then return nil end
  for _, slot in ipairs({ 3, 10, 1, 2, 4, 5, 6, 7, 8, 9 }) do
    local it = player:getInventoryItem(slot)
    if it and it:getId() == item:getId() then return C.keyOf({ { i = slot, id = item:getId() } }) end
  end
  return nil
end

local function onOpen(container, previous)
  local item = container and container:getContainerItem()
  if not item then return end
  local key
  key, pending = C.takePending(pending, item:getId(), nowMs(), container:getId())
  keyById[container:getId()] = key or slotKey(container)
end

local function onClose(container)
  if container then keyById[container:getId()] = nil end
end

function K.keyOf(container)
  return container and keyById[container:getId()] or nil
end

local function containerOf(key)
  for id, k in pairs(keyById) do
    if k == key then
      local c = g_game.getContainer(id)
      if c and c.window and not c.window:isDestroyed() then return c end
    end
  end
  return nil
end

-- ---------------------------------------------------------------- snapshot
function K.snapshot()
  local windows = {}
  local order = { left = 0, right = 0 }
  for _, p in ipairs(M.sidePanels and M.sidePanels() or {}) do
    order[p.side] = (order[p.side] or 0) + 1
    local index = 0
    for _, w in ipairs(p.widget:getChildren()) do
      if M.isMini and M.isMini(w) then
        index = index + 1
        local c = w.container
        local key = c and keyById[c:getId()]
        if key and w:isExplicitlyVisible() then
          local bar = w:getChildById('miniwindowScrollBar')
          windows[#windows + 1] = { key = key, panel = p.id, side = p.side, panelOrder = order[p.side], index = index,
            height = w:getHeight(), minimized = w:isOn(), scroll = bar and bar.getValue and bar:getValue() or nil }
        end
      end
    end
  end
  return C.snapshot(windows)
end

-- ---------------------------------------------------------------- opening
local function openStep(key, onDone, token)
  local steps = C.parse(key)
  if not steps then return onDone(nil) end
  local found = containerOf(key)
  if found then return onDone(found) end
  local player = g_game.getLocalPlayer()
  if not player or not origOpen then return onDone(nil) end
  local item
  if #steps == 1 then
    item = player:getInventoryItem(steps[1].i)
    if not item or item:getId() ~= steps[1].id then return onDone(nil) end
  else
    local parent = containerOf(C.parentKey(key))
    if not parent then return onDone(nil) end
    local list, used = {}, {}
    for _, other in pairs(keyById) do
      local s = C.parse(other)
      if s and #s == #steps and C.parentKey(other) == C.parentKey(key) then used[s[#s].i] = true end
    end
    for i, it in ipairs(parent:getItems()) do
      list[#list + 1] = { index = i - 1, id = it:getId(), container = it:isContainer() }
    end
    local idx = C.resolve(list, steps[#steps], used)
    item = idx and parent:getItem(idx)
    if not item then return onDone(nil) end
    -- the window keeps the saved key: the bag is the one the layout knew, wherever it moved inside the parent
  end
  local cid = origOpen(item)
  pending[#pending + 1] = { key = key, id = item:getId(), cid = tonumber(cid), at = nowMs() }
  local waited = 0
  local function poll()
    if token ~= run then return end
    local c = containerOf(key)
    if c then return onDone(c) end
    waited = waited + 100
    if waited >= C.WAIT_MS then return onDone(nil) end
    later(poll, 100)
  end
  later(poll, 100)
end

-- opens the keys one by one (each after the one before answered), then calls done(opened = { [key] = container })
local function openAll(keys, done)
  run = run + 1
  local token = run
  local opened, i = {}, 0
  local function nextOne()
    if token ~= run or not g_game.isOnline() then return end
    i = i + 1
    if i > #keys then return done(opened) end
    openStep(keys[i], function(c)
      if token ~= run then return end
      if c then opened[keys[i]] = c end
      later(nextOne, C.GAP_MS)
    end, token)
  end
  nextOne()
end

-- the restored windows to their panel, order, height (not on a phone: game_mobilebag sizes them) and scroll
local function place(saved)
  local existing, first, byId = M.panelsMaps()
  local list = C.placement(saved, existing, first)
  local windows = {}
  for _, e in ipairs(list) do
    local c = containerOf(e.key)
    local w = c and c.window
    if w and byId[e.panel] then
      windows[#windows + 1] = { w = w, e = e }
      local parent = w:getParent()
      if parent then parent:removeChild(w) end
    end
  end
  for _, x in ipairs(windows) do
    local target = byId[x.e.panel]
    target:insertChild(math.max(1, math.min(tonumber(x.e.index) or 1, target:getChildCount() + 1)), x.w)
    if x.e.minimized then
      if not x.w:isOn() then pcall(x.w.minimize, x.w, true) end
    else
      if x.w:isOn() then pcall(x.w.maximize, x.w, true) end
      if x.e.height and not isMobile() then pcall(x.w.setHeight, x.w, x.e.height) end
    end
  end
  -- a saved set that no longer fits (a smaller window than at logout) shrinks towards the minimum heights, the biggest
  -- container first, and nothing closes (base patch 0191, O485); a set that fits is left as it was saved
  local ui = modules.game_interface
  for _, target in pairs(byId) do
    if ui and ui.fitPanelWithoutClosing then pcall(ui.fitPanelWithoutClosing, target) end
    if target.fitAll then pcall(target.fitAll, target) end
  end
  -- the scroll once the heights are final
  addEvent(function()
    for _, x in ipairs(windows) do
      local bar = not x.w:isDestroyed() and x.w:getChildById('miniwindowScrollBar')
      if bar and x.e.scroll and bar.setValue then pcall(bar.setValue, bar, x.e.scroll) end
    end
  end)
end

function K.restore(saved, done)
  local entries = C.entries(saved)
  if #entries == 0 or not K.enabled() then
    if done then done() end
    return
  end
  local open = {}
  for _, key in pairs(keyById) do open[key] = true end
  local plan = C.plan(entries, open)
  local keys, transient = {}, {}
  for _, p in ipairs(plan) do
    keys[#keys + 1] = p.key
    if p.transient then transient[p.key] = true end
  end
  K.busy = true
  openAll(keys, function(opened)
    -- the parents opened only to reach a child close again
    for key in pairs(transient) do
      local c = opened[key]
      if c then pcall(g_game.close, c) end
    end
    -- after game_containers has sized the new windows (its addEvent)
    later(function()
      pcall(place, entries)
      K.busy = false
      if done then done() end
    end, 200)
  end)
end

-- Find my item: open the containers of steps (game_stash stashfind.lua F.steps) and flash the item's slot
local function flash(container, at)
  local panel = container and container.itemsPanel
  local slot = panel and at and panel:getChildById('item' .. at)
  if not slot then return end
  slot:setBorderWidth(2)
  slot:setBorderColor('#ffd040')
  scheduleEvent(function()
    if not slot:isDestroyed() then slot:setBorderWidth(0) end
  end, 2500)
end

function K.openPath(steps, at)
  local key = C.keyOf(steps)
  if not key then return false end
  K.busy = false -- a restore still running stops here (openAll runs one list at a time)
  local keys, k = {}, key
  while k do
    table.insert(keys, 1, k)
    k = C.parentKey(k)
  end
  openAll(keys, function(opened)
    local c = opened[key]
    if c then
      if c.window and c.window.raise then pcall(c.window.raise, c.window) end
      later(function() flash(c, at) end, 150)
    elseif modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr('That container is not where it was. Search again.'))
    end
  end)
  return true
end

-- ---------------------------------------------------------------- lifecycle (layout.lua calls these)
function K.reset()
  run = run + 1
  stopEvents()
  keyById, pending = {}, {}
  K.busy = false
end

function K.init()
  hook()
  connect(Container, { onOpen = onOpen, onClose = onClose })
  -- windows open before this module loaded (a reload): their keys are unknown, the slot rule names the backpack
  for _, c in pairs(g_game.getContainers and g_game.getContainers() or {}) do
    if c and not keyById[c:getId()] then keyById[c:getId()] = slotKey(c) end
  end
end

function K.terminate()
  K.reset()
  disconnect(Container, { onOpen = onOpen, onClose = onClose })
  unhook()
end
