-- chunkname: @/mods/client_chaos_popupqueue/popupqueue.lua
-- ChaosPopupQueue (F46, O772): centre popups that open by themselves wait their turn, one on screen at a time.
--   ChaosPopupQueue.request(key, open, isOpen)  open() shows the popup, isOpen() says it is still on screen
--   ChaosPopupQueue.cancel(key)                  the popup is no longer wanted (its window closed before its turn)
-- Other popups on screen also hold the queue: a message box (displayGeneralBox: the Helper's "New spell available"),
-- a server modal dialog, and the windows of BLOCKER_IDS. A caller without the queue (module not loaded) opens at once.
local L = PopupQueueLogic
local TICK_MS = 200
local BLOCKER_IDS = { 'deathRecapWindow', 'patchNotesWindow' }

local state = L.new()
local tickEvent

local function visible(w)
  return w and not w:isDestroyed() and w:isVisible()
end

local function foreignBlocked()
  local md = modules.game_modaldialog
  if md and md.modalDialog then return true end
  if not rootWidget then return false end
  for _, c in ipairs(rootWidget:getChildren()) do
    if c.getClassName and c:getClassName() == 'UIMessageBox' and visible(c) then return true end
  end
  for _, id in ipairs(BLOCKER_IDS) do
    if visible(rootWidget:recursiveGetChildById(id)) then return true end
  end
  return false
end

local function currentOpen()
  local cur = state.current
  if not cur then return false end
  local ok, open = pcall(cur.isOpen)
  return ok and open and true or false
end

local function run(entry)
  local ok, err = pcall(entry.open)
  if not ok then g_logger.warning('[popupqueue] ' .. tostring(entry.key) .. ': ' .. tostring(err)) end
end

local tick
tick = function()
  tickEvent = nil
  local entry = L.step(state, g_clock.millis(), foreignBlocked(), currentOpen())
  if entry then run(entry) end
  if L.pending(state) then tickEvent = scheduleEvent(tick, TICK_MS) end
end

local function wake()
  if not tickEvent then tickEvent = scheduleEvent(tick, TICK_MS) end
end

local API = {}

function API.request(key, open, isOpen)
  if L.push(state, key, { open = open, isOpen = isOpen or function() return false end }) == 'now' then
    run(state.current)
  end
  wake()
end

function API.cancel(key)
  L.remove(state, key)
end

function API.pending()
  return L.pending(state)
end

local function onGameEnd()
  L.clear(state)
end

function init()
  connect(g_game, { onGameEnd = onGameEnd })
  _G.ChaosPopupQueue = API
end

function terminate()
  disconnect(g_game, { onGameEnd = onGameEnd })
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  L.clear(state)
  if rawget(_G, 'ChaosPopupQueue') == API then _G.ChaosPopupQueue = nil end
end
