-- game_chaosuiscale: the interface scale of Options > Interface (client_settings dataset.lua key uiScale, base patch 0129;
-- steps, limits and value reading in uiscale_logic.lua). The option holds the step index; this file works out the factor
-- for the window (a step the window is too small for is lowered, and comes back when the window grows) and gives it to
-- g_app.scale, which redraws at once: no restart. The saved value is in the client's settings file, so it is per computer.
-- A client without base patch 0129 still scales, but the stretched picture is soft (smooth filter) instead of sharp.
local L = UiScaleLogic

local wanted = L.DEFAULT
local applied = nil          -- last factor given to g_app.scale
local lastW, lastH = 0, 0
local watchEvent = nil

local function windowSize()
  local ok, s = pcall(g_window.getSize)
  if ok and s and s.width and s.height then return s.width, s.height end
  return 0, 0
end

local function apply()
  if g_app.isMobile and g_app.isMobile() then return end   -- the phone client sets its own zoom
  local w, h = windowSize()
  if w <= 0 or h <= 0 then return end                      -- minimised
  local f = L.factor(wanted, w, h)
  if f ~= applied then
    applied = f
    g_app.scale(f)
  end
end

local function watch()
  local w, h = windowSize()
  if w ~= lastW or h ~= lastH then
    lastW, lastH = w, h
    apply()
  end
end

function onOption(value)
  wanted = L.parseSaved(value)
  apply()
end

-- for the options line: the percent wanted and the percent in use for a step index
function info(index)
  local i = L.parseSaved(index)
  local w, h = windowSize()
  if w <= 0 or h <= 0 then return L.percent(i), L.percent(i) end
  return L.percent(i), L.percent(L.effectiveIndex(i, w, h))
end

function getWanted()
  return wanted
end

function getApplied()
  return applied or 1
end

function init()
  local cs = modules.client_settings
  if cs and cs.getOption then
    local ok, v = pcall(cs.getOption, 'uiScale')
    if ok then wanted = L.parseSaved(v) end
  end
  lastW, lastH = windowSize()
  apply()
  watchEvent = cycleEvent(watch, 500)
end

function terminate()
  removeEvent(watchEvent)
  watchEvent = nil
  if applied and applied ~= 1 then
    applied = 1
    g_app.scale(1)
  end
end
