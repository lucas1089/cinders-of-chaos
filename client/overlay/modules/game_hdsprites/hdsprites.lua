-- game_hdsprites: loads the HD sprite overlay that ships in data/hd (g_sprites.loadHdOverlay, base patch 0196) and applies the
-- option "HD monsters" (Options > Graphics, dataset `hdMonsters`). Add art: client/tools/sprites/gen_hd_overlay.py,
-- client/MANIFEST.md "HD sprite overlay". A client without patch 0196 has no g_sprites.loadHdOverlay: nothing changes.
local L = HdSpritesLogic

local function hasEngine()
  return g_sprites and g_sprites.loadHdOverlay and g_sprites.setHdOverlayEnabled
end

local function setting()
  local cs = modules.client_settings
  if not (cs and cs.getOption) then return nil end
  local ok, value = pcall(cs.getOption, L.OPTION)
  if ok then return value end
  return nil
end

-- phones: off the first time, through the settings module so the checkbox follows
local function mobileDefault()
  local isMobile = g_app and g_app.isMobile and g_app.isMobile() or false
  local okFlag, done = pcall(g_settings.getBoolean, L.MOBILE_FLAG)
  if not L.mobileDefault(isMobile, okFlag and done) then return end
  local cs = modules.client_settings
  local opts = cs and cs.GameOptions
  if not (opts and opts.getDataSet and opts.setOption and opts:getDataSet(L.OPTION)) then return end
  pcall(opts.setOption, opts, L.OPTION, false)
  pcall(g_settings.set, L.MOBILE_FLAG, true)
end

-- the settings module calls this when the value is applied (dataset.lua, base patch 0196); the sprites that are already
-- built keep their picture until the client restarts, which the option says
function onOption(value)
  if not hasEngine() then return end
  g_sprites.setHdOverlayEnabled(L.isOn(value))
end

function init()
  if not hasEngine() then return end
  pcall(mobileDefault)
  g_sprites.setHdOverlayEnabled(L.isOn(setting()))
  local count = g_sprites.loadHdOverlay(L.DIR)
  g_logger.info('[hdsprites] ' .. L.summary(count, g_sprites.isHdOverlayEnabled()))
end

function terminate()
  if hasEngine() and g_sprites.unloadHdOverlay then g_sprites.unloadHdOverlay() end
end
