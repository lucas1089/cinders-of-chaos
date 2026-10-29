-- Phone data (O313): the start-up step of an Android phone, run by client_chaos_updater/bootstrap.lua (itself run by
-- init.lua before any module is discovered). Only client API: g_resources, g_logger.
--
-- Mounts chaos_update/android, the plain game data the first-start screen downloaded and unpacked, through PhysFS in
-- front of data.zip (g_resources.mountDataFolder, base patch 0167): the sprite shards are read from disk on demand.
-- It is mounted only when the last apply finished ("status=ok"). On a new APK (another package id) the Lua and art of the
-- older APK in that folder are removed first, since they would hide the new data.zip; the game data (data/things) stays.
-- Sets CHAOS_UPDATE_BOOT = { packageId, mounted, state } like the desktop bootstrap, for cleanup_boot.lua.
--
-- Returns a function(packageId); bootstrap.lua calls it.

return function(packageId)
  local U = dofile('/modules/client_chaos_updater/updater_core.lua')
  local C = dofile('/modules/client_chaos_firststart/firststart_core.lua')

  local function read(path)
    if not g_resources.fileExists('/' .. path) then return '' end
    local ok, text = pcall(g_resources.readFileContents, '/' .. path)
    return ok and text or ''
  end

  local st = U.parseState(read(C.STATE))
  CHAOS_UPDATE_BOOT = { packageId = packageId, mounted = false, state = st, phone = true }

  if U.offByEnv(os.getenv) then
    g_logger.info('phone data: off (' .. U.OFF_ENV .. ' is set): data folder not mounted')
    return
  end
  if not g_resources.mountDataFolder then
    g_logger.warning('phone data: this client cannot mount the data folder (base patch 0167)')
    return
  end

  -- a new APK: the old APK's Lua and art in the folder go, the game data stays
  if st.package and st.package ~= '' and st.package ~= packageId and g_resources.directoryExists('/' .. C.TREE) then
    local function names(dir)
      local ok, list = pcall(g_resources.listDirectoryFiles, dir, false, false, false)
      return ok and list or {}
    end
    local removed = 0
    for _, rel in ipairs(C.prunePaths(names('/' .. C.TREE), names('/' .. C.TREE .. '/data'))) do
      if g_resources.removeUpdateTree(C.TREE .. '/' .. rel) then removed = removed + 1 end
    end
    g_logger.info(('phone data: new client package; %d old folders removed, the game data kept'):format(removed))
  end
  if st.package ~= packageId and st.status and st.status ~= '' then
    st.package = packageId
    pcall(g_resources.writeFileContents, '/' .. C.STATE, U.formatState(st))
  end

  if st.status == 'ok' and g_resources.directoryExists('/' .. C.TREE) then
    if g_resources.mountDataFolder(C.TREE) then
      CHAOS_UPDATE_BOOT.mounted = true
      g_logger.info(('phone data: update %d mounted'):format(st.version))
    else
      g_logger.warning('phone data: the data folder could not be mounted')
    end
  elseif st.status and st.status ~= '' then
    g_logger.info(('phone data: data folder not used (%s)'):format(st.status))
  else
    g_logger.info('phone data: no game data yet; the first-start screen downloads it')
  end
end
