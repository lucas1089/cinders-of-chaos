-- Cinders of Chaos signed updater: start-up step, run by init.lua before any module is discovered
-- (client/base-patches/0031-signed-updater.patch). Only client API: g_resources, g_crypt, g_app, g_logger.
--
-- Mounts chaos_update/files (verified update files in the write dir) in front of the client's own files when the
-- last apply finished ("status=ok") and was made for this client package. Otherwise the client starts with its own
-- install files and the updater module checks again on the login screen.

local core = dofile('/modules/client_chaos_updater/updater_core.lua')

local function packageId()
  local init = ''
  pcall(function() init = g_resources.readFileContents('/init.lua') end)
  return g_crypt.sha256Encode(table.concat({
    g_app.getBuildDate(), g_app.getBuildCommit(), g_app.getBuildArch(), init
  }, '\n'), false)
end

local text = ''
if g_resources.fileExists('/' .. core.STATE) then
  text = g_resources.readFileContents('/' .. core.STATE)
end
local st = core.parseState(text)
local id = packageId()
CHAOS_UPDATE_BOOT = { packageId = id, mounted = false, state = st }

if core.shouldMount(st, id) then
  if g_resources.mountUpdateDir(core.TREE) then
    CHAOS_UPDATE_BOOT.mounted = true
    g_logger.info(('updater: update %d mounted'):format(st.version))
  else
    g_logger.warning('updater: the update folder could not be mounted')
  end
elseif st.status and st.status ~= '' then
  g_logger.info(('updater: update folder not used (%s)'):format(st.package ~= id and 'other client package' or st.status))
end
