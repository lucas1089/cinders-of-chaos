-- game_visualfx: a short pulse on an action bar slot when its cooldown ends (O229, base patch 0161). The base action bar
-- calls ChaosCooldownPulse.onEnd(button, duration, elapsed) when the timer of a slot's cooldown runs out (removeCooldown);
-- cooldownpulse_logic.lua decides (cooldown of 3 s or more that ran its course) and gives the opacity curve (280 ms: a rise
-- in 40 ms, then a fade). The pulse is a pale layer (style ChaosCooldownFlash) put on the slot and destroyed at the end;
-- one 16 ms cycleEvent runs only while a pulse is alive. Option cooldownPulse (Options > Graphics, default on); off, or
-- without the patch, nothing happens.
local L = CooldownPulseLogic

ChaosCooldownPulse = {}
local P = ChaosCooldownPulse
-- the module is sandboxed: the global must be set on _G for the base's action bar (base patch 0161)
_G.ChaosCooldownPulse = P

local enabled = false
local tracker = L.newTracker()
local widgets = {} -- key -> the layer on the slot
local keys = setmetatable({}, { __mode = 'k' }) -- slot widget -> key
local nextKey = 0
local tick = nil

local function destroyLayer(key)
  local w = widgets[key]
  widgets[key] = nil
  if w then pcall(function() w:destroy() end) end
end

local function onTick()
  local live, done = L.step(tracker, g_clock.millis())
  for key, a in pairs(live) do
    local w = widgets[key]
    local ok = w and pcall(function() w:setOpacity(a) end)
    if not ok then L.remove(tracker, key); widgets[key] = nil end
  end
  for _, key in ipairs(done) do destroyLayer(key) end
  if not L.active(tracker) and tick then removeEvent(tick); tick = nil end
end

function P.setEnabled(on)
  enabled = on and true or false
  if not enabled then P.clear() end
end

function P.isEnabled() return enabled end

-- the hook (base patch 0161); every failure is swallowed by the caller's pcall, and a slot that went away is dropped
function P.onEnd(button, duration, elapsed)
  if not enabled or not button then return end
  if not L.shouldPulse(duration, elapsed) then return end
  local key = keys[button]
  if not key then nextKey = nextKey + 1; key = nextKey; keys[button] = key end
  if widgets[key] == nil then
    if not L.start(tracker, key, g_clock.millis()) then return end
    local w = g_ui.createWidget('ChaosCooldownFlash', button)
    if not w then L.remove(tracker, key); return end
    widgets[key] = w
  else
    L.start(tracker, key, g_clock.millis()) -- a layer already there: restart the curve
  end
  if not tick then tick = cycleEvent(onTick, 16) end
end

-- game end, option off, terminate: every layer goes, nothing is left running
function P.clear()
  if tick then removeEvent(tick); tick = nil end
  for key in pairs(widgets) do destroyLayer(key) end
  tracker = L.newTracker()
end

function P.terminate()
  P.clear()
  enabled = false
  if _G.ChaosCooldownPulse == P then _G.ChaosCooldownPulse = nil end
end
