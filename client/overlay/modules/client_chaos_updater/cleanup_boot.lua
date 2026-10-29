-- Clean start after an update: start-up step, run by skin_boot.lua (itself run by init.lua before any module is
-- discovered, base patch 0159) ahead of the skin copy. Only client API: g_resources, g_logger, g_app.
--
-- On a new client package (the launcher or a fresh download) and on a new in-game update it removes everything in the
-- per-user write folder that is not the player's own data, so no old file of the write folder (an old update tree,
-- old skin images, downloads) hides the new art. cleanup_core.lua has the keep-list and the reasons.
-- CHAOS_CLEAN_OFF=1 in the environment: never runs (tests).
-- Sets the global ChaosCleanBoot = { ran, reason, removed, failed, kept } .

local core = dofile('/modules/client_chaos_updater/cleanup_core.lua')
local updater = dofile('/modules/client_chaos_updater/updater_core.lua')

ChaosCleanBoot = { ran = false }

local function norm(p)
  p = tostring(p or ''):gsub('\\', '/'):gsub('/+$', '')
  if g_app and g_app.getOs and tostring(g_app.getOs()):lower():find('windows') then p = p:lower() end
  return p
end

local function run()
  if os.getenv and (os.getenv('CHAOS_CLEAN_OFF') or '') ~= '' and os.getenv('CHAOS_CLEAN_OFF') ~= '0' then return end
  local boot = CHAOS_UPDATE_BOOT
  if type(boot) ~= 'table' or type(boot.packageId) ~= 'string' or boot.packageId == '' then return end
  local writeDir = norm(g_resources.getWriteDir and g_resources.getWriteDir() or '')
  if writeDir == '' then return end   -- no write folder known: touch nothing

  local function read(path)
    if not g_resources.fileExists(path) then return '' end
    return g_resources.readFileContents(path)
  end
  local baseline = 0
  if type(Services) == 'table' and type(Services.update) == 'table' then baseline = updater.baseline(Services.update.baseline) end
  local d = core.decide({
    packageId = boot.packageId,
    stamp = core.parseStamp(read(core.STAMP)),
    treeState = updater.parseState(read('/' .. updater.STATE)),
    treeExists = g_resources.directoryExists('/' .. core.TREE_NAME),
    baseline = baseline,
  })
  if not d.run then return end

  local fs = {
    list = function(path) return g_resources.listDirectoryFiles(path, false, false, false) end,
    isDir = function(path) return g_resources.directoryExists(path) end,
    inWrite = function(path) return norm(g_resources.getRealDir(path)) == writeDir end,
    delete = function(path) return g_resources.deleteFile(path) end,
  }
  -- a stale tree is already mounted by bootstrap.lua when it was made for this package: take it out first
  if not d.keepTree and boot.mounted and g_resources.unmountUpdateOverlay then
    pcall(g_resources.unmountUpdateOverlay)
    boot.mounted = false
    boot.state = updater.parseState('')
  end
  local res = core.sweep(fs, { keepTree = d.keepTree })
  -- the stamp is written even when something could not be removed (a file in use): the next change cleans again
  pcall(g_resources.writeFileContents, core.STAMP, core.formatStamp(boot.packageId, d.update))
  ChaosCleanBoot = { ran = true, reason = d.reason, removed = res.removed, failed = res.failed, kept = res.kept }
  g_logger.info(('clean start in %s: %s; %d removed, %d not removable, player data kept (%s)')
    :format(writeDir, d.reason, res.removed, res.failed, table.concat(res.kept, ', ')))
end

local ok, err = pcall(run)
if not ok then g_logger.warning('clean start: ' .. tostring(err)) end
