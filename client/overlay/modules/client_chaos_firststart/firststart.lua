-- Phone data (O313): the first-start screen of the Android client (client/MANIFEST.md "Phone data",
-- docs/ANDROID_CLIENT.md section 3). Only active on Android; the desktop updater (client_chaos_updater) is off there.
--
-- The APK has no sprite pair. On start this module fetches the signed manifest (Services.update.manifest, checked with the
-- Ed25519 key of init.lua), takes the phone list ("android" section), compares it with what the phone has and, when game
-- data is missing, shows a screen: the size, Wi-Fi advice, the free space against what is needed (data plus 0.5 GB
-- staging), a Download button, then progress with pause and resume, retry after a failure, and a restart at the end.
-- The download is ChaosUpdateCore.download (parallel ranged parts, resume, retries, SHA-256 of every blob and of what
-- it decrypts to); the verified blobs are unpacked into the plain tree chaos_update/android (g_resources.unpackUpdateBlob),
-- which the next start mounts in front of data.zip (boot.lua). Logging in is blocked while the screen is up.
-- A small update (Lua, art) with the game data in place starts by itself, with the progress screen but without asking.
-- Logcat lines: "firststart: screen shown (...)" when the screen first appears (the emulator smoke test of
-- android-client.yml looks for it).

ChaosFirstStart = ChaosFirstStart or {}
local F = ChaosFirstStart
local U = ChaosUpdateCore
local C = ChaosFirstStartCore

local HTTP_TIMEOUT = 20          -- seconds without a byte before a request fails
local HASH_SLICE_MS = 12         -- hashing runs in slices so the screen keeps drawing

local cfg, boot
local blocker, panel
local httpOps, timers = {}, {}
local phase = 'idle'
local needsData = false
local shownLogged = false
local job, unpackJob, hashEvent
local origDoLogin
local manifest, plan, blobs, summary
local pausing = false
local result = {}

-- ---------------------------------------------------------------- small helpers

local function alive(w) return w and not w:isDestroyed() end

local function later(ms, fn)
  local ev
  ev = scheduleEvent(function()
    timers[ev] = nil
    fn()
  end, ms)
  timers[ev] = true
  return ev
end

local function dirOf(path) return path:match('^(.*)/[^/]*$') end

local function readText(path)
  if not g_resources.fileExists('/' .. path) then return '' end
  local ok, text = pcall(g_resources.readFileContents, '/' .. path)
  return ok and text or ''
end

local function writeText(path, text)
  g_resources.makeDir('/' .. dirOf(path))
  return g_resources.writeFileContents('/' .. path, text)
end

local function loadState() return U.parseState(readText(C.STATE)) end

local function saveState(st) return writeText(C.STATE, U.formatState(st)) end

local function setPhase(event)
  local nxt = C.nextPhase(phase, event)
  if not nxt then
    g_logger.warning(('firststart: event %s does not apply in %s'):format(event, phase))
    return false
  end
  phase = nxt
  return true
end

-- ---------------------------------------------------------------- HTTP (g_http, results with status and headers)

local function onGet(id, url, err, res)
  local op = httpOps[id]
  if not op then return end
  httpOps[id] = nil
  local r = type(res) == 'table' and res or { body = res }
  op.onDone({ status = tonumber(r.status) or 0, headers = r.headers or {}, body = r.body or '', error = err or r.error })
end

local function onGetProgress(id, url, progress)
  local op = httpOps[id]
  if op and op.onProgress then op.onProgress(tonumber(progress) or 0) end
end

local function httpGet(url, headers, onProgress, onDone)
  local id = g_http.get(url, HTTP_TIMEOUT, headers or {})
  httpOps[id] = { onProgress = onProgress, onDone = onDone }
  return id
end

local function httpCancel(id)
  httpOps[id] = nil
  g_http.cancel(id)
end

-- ---------------------------------------------------------------- screen

local function setText(id, text)
  if alive(panel) then panel:getChildById(id):setText(text or '') end
end

local function buttons(start, pause, retry, play, restart)
  if not alive(panel) then return end
  panel:getChildById('startButton'):setVisible(start and true or false)
  panel:getChildById('pauseButton'):setVisible(pause and true or false)
  panel:getChildById('retryButton'):setVisible(retry and true or false)
  panel:getChildById('playButton'):setVisible(play and true or false)
  panel:getChildById('restartButton'):setVisible(restart and true or false)
end

local function showPanel(why)
  if not alive(blocker) then
    blocker = g_ui.createWidget('ChaosFirstStartBlocker', rootWidget)
  end
  if not alive(panel) then
    panel = g_ui.createWidget('ChaosFirstStartPanel', rootWidget)
    panel:getChildById('startButton').onClick = function() F.start() end
    panel:getChildById('pauseButton').onClick = function() F.togglePause() end
    panel:getChildById('retryButton').onClick = function() F.check() end
    panel:getChildById('playButton').onClick = function() F.dismiss() end
    panel:getChildById('restartButton').onClick = function() F.restart() end
  end
  blocker:raise()
  panel:raise()
  buttons(false, false, false, false, false)
  if not shownLogged then
    shownLogged = true
    g_logger.info('firststart: screen shown (' .. tostring(why) .. ')')
  end
end

local function hidePanel()
  if alive(panel) then panel:destroy() end
  if alive(blocker) then blocker:destroy() end
  panel, blocker = nil, nil
end

local function progress(percent, detail, note)
  if not alive(panel) then return end
  panel:getChildById('bar'):setPercent(math.max(0, math.min(100, math.floor(percent))))
  if detail then setText('progressText', detail) end
  if note then setText('note', note) end
end

function F.blocking()
  return C.blocksLogin(phase, needsData)
end

function F.dismiss()
  if phase == 'blocked' or needsData then return end
  phase = 'uptodate'
  hidePanel()
end

-- ---------------------------------------------------------------- problems

-- the manifest or the download failed. Without game data the screen stays with a Retry button; with it the player
-- plays on (the update comes at the next start).
local function problem(title, why, event)
  g_logger.warning(('firststart: %s (%s)'):format(title, tostring(why)))
  result.problem = title
  if not needsData and phase == 'checking' then
    phase = 'offline'
    hidePanel()
    return
  end
  setPhase(event or 'fail')
  showPanel('problem')
  setText('status', title)
  setText('detail', '')
  progress(0, tostring(why or ''), needsData and tr('The game data is needed to play. Check the connection and try again.')
    or tr('You can play with the current files.'))
  buttons(false, false, true, not needsData, false)
end

-- ---------------------------------------------------------------- download

local downloadIo = {
  get = httpGet,
  cancel = httpCancel,
  size = function(path) return g_resources.fileSize('/' .. path) end,
  read = function(path)
    local ok, data = pcall(g_resources.readFileContents, '/' .. path)
    return ok and data or nil
  end,
  write = function(path, data) return g_resources.writeFileContents('/' .. path, data) end,
  append = function(path, data) return g_resources.appendFileContents('/' .. path, data) end,
  remove = function(path) return g_resources.removeUpdateTree(path) end,
  sha256 = function(path) return g_resources.fileSha256('/' .. path) end,
  plainSha256 = function(path) return g_resources.updateBlobSha256('/' .. path) end,
  rename = function(from, to) return g_resources.moveUpdateFile(from, to) end,
  later = later,
}

local function newState(m, status)
  return {
    version = m.version, min_version = m.min_version or 0, min_package = m.min_package or 0,
    package = boot.packageId, applied = os.date('!%Y-%m-%dT%H:%M:%SZ'), enc = U.ENCRYPTION, status = status,
  }
end

local function finishApplied()
  phase = 'restart'
  result.applied = #plan.download
  showPanel('applied')
  setText('status', tr('Game data ready'))
  progress(100, ('%d files, %s'):format(summary.files, U.formatBytes(summary.plainBytes)), tr('Restarting the game...'))
  buttons(false, false, false, false, true)
  if U.restartMode(g_app) ~= 'restart' then
    result.restart = 'manual'
    setText('note', tr('Close the client and start it again to load the update.'))
    return
  end
  later(2500, F.restart)
end

local function unpack()
  setText('status', tr('Unpacking the game data'))
  progress(0, '', tr('This takes a few minutes. Keep the screen on.'))
  buttons(false, false, false, false, false)
  saveState(newState(manifest, 'applying'))
  local ix = C.parseIndex(readText(C.INDEX))
  local unpackIo = {
    unpack = function(from, to) return g_resources.unpackUpdateBlob(from, to) end,
    remove = function(path) return g_resources.removeUpdateTree(path) end,
    index = function(path, sha, size)
      ix[path] = { sha = sha, size = size }
      g_resources.appendFileContents('/' .. C.INDEX, C.indexLine(path, sha, size))
    end,
    later = later,
  }
  unpackJob = C.unpack({
    blobs = blobs, io = unpackIo,
    onProgress = function(s)
      progress(s.bytesTotal > 0 and 100 * s.bytesDone / s.bytesTotal or 100,
        ('%d / %d files   %s / %s'):format(s.filesDone, s.filesTotal, U.formatBytes(s.bytesDone), U.formatBytes(s.bytesTotal)))
    end,
    onDone = function(ok, err)
      unpackJob = nil
      if phase == 'stopped' then return end
      if not ok then
        return problem(tr('Game data could not be unpacked'), err, 'fail')
      end
      for _, p in ipairs(plan.stale or {}) do
        g_resources.removeUpdateTree(C.TREE .. '/' .. p)
        ix[p] = nil
      end
      writeText(C.INDEX, C.formatIndex(ix))
      g_resources.removeUpdateTree(U.STAGING:sub(1, -2))
      if not saveState(newState(manifest, 'ok')) then
        return problem(tr('Game data could not be unpacked'), 'cannot write the state', 'fail')
      end
      g_logger.info(('firststart: update %d unpacked: %d files, %s'):format(manifest.version, summary.files,
        U.formatBytes(summary.plainBytes)))
      finishApplied()
    end,
  })
end

local function download()
  local workers = C.workerCount(tonumber(g_settings.getValue('chaos-update-parallel')), manifest.parallel)
  result.workers = workers
  pausing = false
  showPanel('download')
  setText('status', tr('Downloading the game data'))
  setText('detail', '')
  buttons(false, true, false, false, false)
  if alive(panel) then panel:getChildById('pauseButton'):setText(tr('Pause')) end
  g_resources.makeDir('/' .. U.STAGING)
  local t0 = g_clock.millis()
  local lastBytes, lastT, speed = 0, t0, 0
  job = U.download({
    blobs = blobs, workers = workers, io = downloadIo,
    onProgress = function(s)
      local now = g_clock.millis()
      if now - lastT >= 500 then
        speed = (s.bytesDone - lastBytes) * 1000 / (now - lastT)
        lastBytes, lastT = s.bytesDone, now
      end
      progress(s.bytesTotal > 0 and 100 * s.bytesDone / s.bytesTotal or 100,
        ('%d / %d files   %s / %s'):format(s.filesDone, s.filesTotal, U.formatBytes(s.bytesDone), U.formatBytes(s.bytesTotal)),
        ('%s/s'):format(U.formatBytes(math.max(0, speed))))
    end,
    onDone = function(ok, err)
      job = nil
      if phase == 'stopped' then return end
      if not ok then
        if pausing and err == 'canceled' then
          setPhase('pause')
          setText('status', tr('Download paused'))
          setText('note', tr('Press Resume to go on. What is downloaded stays on the phone.'))
          if alive(panel) then panel:getChildById('pauseButton'):setText(tr('Resume')) end
          buttons(false, true, false, false, false)
          return
        end
        return problem(tr('Download failed'), err, 'fail')
      end
      result.seconds = (g_clock.millis() - t0) / 1000
      g_logger.info(('firststart: downloaded %d files (%s) in %.1f s with %d parallel'):format(
        #blobs, U.formatBytes(summary.blobBytes), result.seconds, workers))
      setPhase('done')
      unpack()
    end,
  })
end

-- Download button
function F.start()
  if phase ~= 'ready' then return end
  setPhase('start')
  download()
end

-- Pause / Resume button
function F.togglePause()
  if phase == 'downloading' and job then
    pausing = true
    job.cancel()
  elseif phase == 'paused' then
    setPhase('resume')
    download()
  end
end

function F.restart()
  if phase ~= 'restart' then return end
  if U.restartMode(g_app) ~= 'restart' then
    result.restart = 'manual'
    return
  end
  g_logger.info('firststart: restarting the client to mount the game data')
  local ok, err = pcall(function() g_app.restart() end)
  if not ok then g_logger.warning('firststart: restart failed: ' .. tostring(err)) end
end

-- ---------------------------------------------------------------- compare the phone list with the phone

-- hashes are time-sliced; the tree is compared by the index, data.zip's files by their SHA-256
local function compareFiles(entries, scopeName, onDone)
  local index = C.parseIndex(readText(C.INDEX))
  local out = { download = {}, stale = {} }
  local i, n = 1, #entries
  local function slice()
    hashEvent = nil
    local t0 = g_clock.millis()
    while i <= n and g_clock.millis() - t0 < HASH_SLICE_MS do
      local e = entries[i]
      local ix = index[e.path]
      local treeHash = ix and g_resources.fileSize('/' .. C.TREE .. '/' .. e.path) == ix.size and ix.sha or nil
      local visible
      if treeHash == nil then
        visible = g_resources.fileExists('/' .. e.path) and g_resources.fileSha256('/' .. e.path) or nil
        if visible == '' then visible = nil end
      end
      if C.decide(e, treeHash, visible) == 'download' then out.download[#out.download + 1] = e end
      i = i + 1
    end
    progress(100 * (i - 1) / math.max(1, n), ('%d / %d files'):format(i - 1, n))
    if i <= n then
      hashEvent = scheduleEvent(slice, 1)
      return
    end
    if scopeName == 'all' then out.stale = C.staleTree(index, entries) end
    onDone(out)
  end
  slice()
end

local function ready()
  -- a screen with the size, the advice and the free space; the player starts the download
  local free = g_resources.getFreeSpace and g_resources.getFreeSpace() or -1
  local staged = C.stagedBytes(blobs, downloadIo.size)
  local needed = C.spaceNeeded(summary.plainBytes, staged)
  local fits, missing = C.spaceVerdict(free, needed)
  result.free, result.needed, result.fits = free, needed, fits
  showPanel(summary.firstInstall and 'first start' or 'update')
  setText('status', summary.firstInstall and tr('Game data needed') or tr('Game data update'))
  setText('detail', tr('Download %s of game data (%d files) to this phone. Use Wi-Fi: it is a big download.',
    U.formatBytes(summary.blobBytes), summary.files))
  progress(0, '', '')
  if fits then
    setText('note', free >= 0 and tr('Free space on the phone: %s. Needed: %s.', U.formatBytes(free), U.formatBytes(needed)) or '')
    buttons(true, false, false, false, false)
    if alive(panel) then panel:getChildById('startButton'):setText(tr('Download')) end
  else
    setText('note', tr('Not enough free space: free about %s more and try again.', U.formatBytes(missing)))
    buttons(false, false, true, false, false)
  end
  g_logger.info(('firststart: ready: %d files, download %s, free %s, needed %s'):format(summary.files,
    U.formatBytes(summary.blobBytes), U.formatBytes(free), U.formatBytes(needed)))
end

local function onManifest(r)
  if phase ~= 'checking' then return end
  if (r.error and r.error ~= '') or r.status ~= 200 then
    return problem(tr('Update server unreachable'), (r.error and r.error ~= '') and r.error or ('HTTP ' .. tostring(r.status)),
      'offline')
  end
  local envelope, jerr = U.jsonDecode(r.body)
  if type(envelope) ~= 'table' then
    return problem(tr('Update refused'), 'manifest is not valid JSON (' .. tostring(jerr) .. ')', 'fail')
  end
  local payload, why = U.checkEnvelope(envelope, cfg.publicKey, function(key, msg, sig)
    return g_crypt.ed25519Verify(key, msg, sig)
  end)
  if not payload then return problem(tr('Update refused'), why, 'fail') end
  local m, perr = U.jsonDecode(payload)
  if type(m) ~= 'table' then return problem(tr('Update refused'), 'payload is not valid JSON (' .. tostring(perr) .. ')', 'fail') end
  local st = loadState()
  local valid, reason = U.validateManifest(m, st.version > 0 and st.version or nil)
  if not valid then return problem(tr('Update refused'), reason, 'fail') end
  if (m.min_package or 0) > (cfg.package or 0) then
    -- the APK is too old for this server: a new APK is needed (APK self-update is not built yet)
    phase = 'blocked'
    showPanel('blocked')
    setText('status', tr('A new client download is required'))
    setText('detail', '')
    progress(0, cfg.download ~= '' and cfg.download or tr('Download the new client from the website.'),
      tr('The game files of this client are too old for the server.'))
    buttons(false, false, true, false, false)
    return
  end
  local entries, eerr = C.androidEntries(m)
  if not entries then return problem(tr('Update refused'), eerr, 'fail') end
  manifest = m
  local scoped, scopeName = C.scope(m, entries, cfg.baseline)
  if scopeName == 'things' then
    g_logger.info(('firststart: update %d is older than this APK (%d): only the game data is taken'):format(m.version, cfg.baseline))
  end
  setText('status', tr('Checking the game data'))
  compareFiles(scoped, scopeName, function(p)
    if phase ~= 'checking' then return end
    plan = p
    if #p.download == 0 and #p.stale == 0 then
      saveState(newState(m, 'ok'))
      -- files all in place, but an earlier run stopped before the folder was mounted: one restart mounts it
      local placed = next(C.parseIndex(readText(C.INDEX))) ~= nil
      if placed and not boot.mounted then
        blobs, summary = {}, { files = 0, plainBytes = 0, blobBytes = 0 }
        g_logger.info(('firststart: update %d is in place but not mounted yet'):format(m.version))
        return finishApplied()
      end
      phase = 'uptodate'
      needsData = false
      result.upToDate = m.version
      g_logger.info(('firststart: up to date (update %d, %d files checked)'):format(m.version, #scoped))
      if alive(panel) then
        setText('status', tr('Your client is up to date'))
        progress(100, '', '')
        later(1500, function() if phase == 'uptodate' then F.dismiss() end end)
      end
      return
    end
    blobs = U.blobsFor(p.download)
    for _, b in ipairs(blobs) do b.url = U.blobUrl(cfg.manifest, m.files_url, b.sha) end
    summary = C.summary(p.download)
    if #blobs == 0 then
      -- only tree files to remove
      for _, path in ipairs(p.stale) do g_resources.removeUpdateTree(C.TREE .. '/' .. path) end
      saveState(newState(m, 'ok'))
      phase = 'uptodate'
      hidePanel()
      return
    end
    if C.needsConfirm(summary) then
      setPhase('ready')
      return ready()
    end
    setPhase('start')
    download()
  end)
end

-- ---------------------------------------------------------------- check

function F.check()
  if not cfg or not (phase == 'idle' or phase == 'uptodate' or C.nextPhase(phase, 'retry')) then return end
  if job then job.cancel(); job = nil end
  result = {}
  needsData = not g_resources.fileExists('/' .. C.PROBE)
  phase = C.nextPhase(phase, 'retry') or 'checking'
  if needsData then
    showPanel('no game data')
    setText('status', tr('Checking for game data'))
    setText('detail', '')
    progress(0, '', '')
  end
  local url = cfg.manifest .. (cfg.manifest:find('?', 1, true) and '&' or '?') .. 't=' .. os.time()
  httpGet(url, {}, nil, onManifest)
end

-- for the tests (devexec) and the terminal
function F.status()
  return { phase = phase, needsData = needsData, result = result, mounted = boot and boot.mounted,
           version = loadState().version }
end

-- ---------------------------------------------------------------- module

local function enabled(c)
  return type(c) == 'table' and type(c.manifest) == 'string' and c.manifest ~= ''
end

function F.init()
  g_ui.importStyle('firststart')
  connect(g_http, { onGet = onGet, onGetProgress = onGetProgress })
  if not U.onAndroid(g_app) then return end
  cfg = Services and Services.update
  boot = CHAOS_UPDATE_BOOT or { packageId = '', mounted = false }
  if not enabled(cfg) then
    g_logger.info('firststart: no update server in init.lua (Services.update.manifest); no game data download')
    return
  end
  if U.offByEnv(os.getenv) then
    g_logger.info('firststart: off (' .. U.OFF_ENV .. ' is set): no check')
    return
  end
  if not (g_crypt.ed25519Verify and g_resources.fileSha256 and g_resources.moveUpdateFile and g_resources.updateBlobSha256
          and g_resources.unpackUpdateBlob) then
    g_logger.warning('firststart: this client build cannot unpack game data (base patches 0031, 0103 and 0167)')
    return
  end
  cfg.package = tonumber(cfg.package) or 0
  cfg.baseline = U.baseline(cfg.baseline)
  cfg.download = cfg.download or ''
  if EnterGame and EnterGame.doLogin then
    origDoLogin = EnterGame.doLogin
    EnterGame.doLogin = function(...)
      if F.blocking() then return end
      return origDoLogin(...)
    end
  end
  phase = 'idle'
  F.check()
end

function F.terminate()
  phase = 'stopped'
  if hashEvent then removeEvent(hashEvent); hashEvent = nil end
  if job then job.cancel(); job = nil end
  if unpackJob then unpackJob.cancel(); unpackJob = nil end
  for id in pairs(httpOps) do g_http.cancel(id) end
  httpOps = {}
  for ev in pairs(timers) do removeEvent(ev) end
  timers = {}
  disconnect(g_http, { onGet = onGet, onGetProgress = onGetProgress })
  if origDoLogin and EnterGame then EnterGame.doLogin = origDoLogin end
  origDoLogin = nil
  hidePanel()
end
