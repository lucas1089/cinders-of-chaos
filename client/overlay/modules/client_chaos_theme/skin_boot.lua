-- Interface skin, start-up step: run by init.lua before any module is discovered (client/base-patches/0159-interface-skin.patch).
-- Only client API: g_configs, g_resources, g_logger, os.getenv. Copies the chosen skin's images in front of the client's
-- own files (the write folder is searched first), or takes the last skin's files out for classic; skin_core.lua has the
-- logic and the reason it runs here: images are cached by path, so it must happen before the first window is built.
-- Sets the global ChaosSkinBoot = { selected, skin, copied, changed, error } for client_chaos_theme.

local core = dofile('/modules/client_chaos_theme/skin_core.lua')

local function saved()
  local ok, value = pcall(function()
    local settings = g_configs.getSettings()
    if settings:exists(core.SETTING) then return settings:getValue(core.SETTING) end
    return nil
  end)
  return ok and value or nil
end

local fs = {
  read = function(path)
    if not g_resources.fileExists(path) then return '' end
    return g_resources.readFileContents(path)
  end,
  write = function(path, text) return g_resources.writeFileContents(path, text) end,
  delete = function(path) return g_resources.deleteFile(path) end,
  mkdir = function(path) return g_resources.makeDir(path) end,
  copy = function(from, to) return g_resources.copyFile(from, to) end,
  manifest = function(id)
    local path = core.manifestPath(id)
    if not path or not g_resources.fileExists(path) then return nil end
    return dofile(path)
  end,
}

local selected = core.choose(saved(), os.getenv and os.getenv(core.ENV) or nil)
local ok, result = pcall(core.sync, fs, selected)
if not ok then
  g_logger.warning('interface skin: ' .. tostring(result))
  result = { selected = selected, skin = core.DEFAULT, changed = false, copied = 0, failed = 0, error = tostring(result) }
end
ChaosSkinBoot = result
if result.error then
  g_logger.warning(('interface skin: "%s" not applied (%s), classic is used'):format(selected, result.error))
elseif result.changed then
  g_logger.info(('interface skin: %s, %d files copied'):format(result.skin, result.copied))
end
