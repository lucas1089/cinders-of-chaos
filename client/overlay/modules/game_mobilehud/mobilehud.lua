-- game_mobilehud: phones only. The first game start on a phone switches the three bottom hotkey bars off once
-- (game_actionbar configureActionBar, as the Options checkboxes do), for more room on the small screen (O401, owner
-- 2026-11-04). The g_settings flag keeps it to once: Options can turn a bar back on. Rules in mobilehud_logic.lua.
ChaosMobileHud = ChaosMobileHud or {}
local M = ChaosMobileHud
local L = MobileHudLogic

local active = false
local event = nil

local function done()
  local ok, v = pcall(g_settings.getBoolean, L.FLAG, false)
  return ok and v
end

local function apply()
  event = nil
  if not g_game.isOnline() then return end
  local bars = L.barsToHide(true, done())
  if #bars == 0 then return end
  local ab = modules.game_actionbar
  if not ab or type(ab.configureActionBar) ~= 'function' then return end
  for _, name in ipairs(bars) do pcall(ab.configureActionBar, name, false) end
  pcall(function()
    g_settings.set(L.FLAG, true)
    g_settings.save()
  end)
end

local function onGameStart()
  if event then removeEvent(event) end
  event = scheduleEvent(apply, L.DELAY_MS)
end

function M.init()
  if not g_app.isMobile() then return end
  active = true
  connect(g_game, { onGameStart = onGameStart })
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  if event then removeEvent(event) event = nil end
  if not active then return end
  active = false
  disconnect(g_game, { onGameStart = onGameStart })
end
