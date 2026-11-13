-- game_minimaphd: the HD minimap. Loads the swatch atlas that ships in data/minimap_hd (g_minimap.loadHdAtlas, base patch 0197;
-- client/tools/gen_minimap_swatches.py makes it), registers the shader that moves the water and the lava, and applies the option
-- "HD minimap" (Options > Graphics, dataset `hdMinimap`, default on; no restart). From 2 px per tile up the explored map is drawn
-- from small pictures of the real ground, walls and trees with shadows; below that, and for tiles from an old minimap file, the flat
-- colours of before. A client without patch 0197 has no g_minimap.loadHdAtlas: nothing changes.
local L = MinimapHdLogic

local function setting()
  local cs = modules.client_settings
  if not (cs and cs.getOption) then return nil end
  local ok, value = pcall(cs.getOption, L.OPTION)
  if ok then return value end
  return nil
end

-- phones: the flat map the first time, through the settings module so the checkbox follows
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

-- the settings module calls this when the value is applied (dataset.lua, base patch 0197)
function onOption(value)
  if not L.hasEngine(g_minimap) then return end
  g_minimap.setHdEnabled(L.isOn(value))
end

function init()
  if not L.hasEngine(g_minimap) then return end
  pcall(mobileDefault)
  if g_shaders and g_shaders.createShader then
    local ok, err = pcall(g_shaders.createShader, L.SHADER, L.VERTEX, L.FRAGMENT)
    if not ok then g_logger.warning('[minimaphd] shader: ' .. tostring(err)) end
  end
  g_minimap.setHdMinScale(L.MIN_SCALE)
  g_minimap.setHdEnabled(L.isOn(setting()))
  local count = g_minimap.loadHdAtlas(L.DIR)
  g_logger.info('[minimaphd] ' .. L.summary(count, g_minimap.isHdEnabled()))
end

function terminate()
  if L.hasEngine(g_minimap) and g_minimap.unloadHdAtlas then g_minimap.unloadHdAtlas() end
end
