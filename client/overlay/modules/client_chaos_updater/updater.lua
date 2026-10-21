-- Cinders of Chaos signed updater: the login-screen part (client/MANIFEST.md "Signed updater").
--
-- On start, before anyone logs in: fetch the manifest (Services.update.manifest), check its Ed25519 signature with
-- the key in init.lua, compare SHA-256 hashes of the files the client sees with the manifest, download what differs
-- with a pool of parallel requests (largest first, ranged parts with resume, retries with backoff, each file's hash
-- checked as soon as it is on disk), and only when every file is in and verified move them into
-- chaos_update/files in one step and restart. bootstrap.lua mounts that folder at the next start.
-- Unreachable server: play with the current files, unless Services.update.required or a minimum the server set.
-- Never downloads native code: the exe and its DLLs come only with the client package (core.DENIED_EXT).
-- Never applies a manifest older than the package's own files (Services.update.baseline, the release number the package
-- was built as). Restarts by itself only on an exe with base patch 0101 (g_app.canRestart); an older exe's restart could
-- abort, so there the player closes and starts the client. CHAOS_UPDATE_OFF=1 in the environment turns it off (CI).

ChaosUpdater = ChaosUpdater or {}
local U = ChaosUpdater
local core = ChaosUpdateCore

local HTTP_TIMEOUT = 20          -- seconds without a byte before a request fails
local HASH_SLICE_MS = 12         -- hashing runs in slices so the login screen keeps drawing
local CACHE = core.ROOT .. 'hashcache.txt'

local cfg, boot
local blocker, panel
local httpOps, timers = {}, {}
local phase = 'idle'
local job, hashEvent
local origDoLogin
local manifest, manifestState
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

local function loadState()
  return core.parseState(readText(core.STATE))
end

local function saveState(st)
  return writeText(core.STATE, core.formatState(st))
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

-- ---------------------------------------------------------------- panel

local function setText(id, text)
  if alive(panel) then panel:getChildById(id):setText(text or '') end
end

local function buttons(retry, play, restart)
  if not alive(panel) then return end
  panel:getChildById('retryButton'):setVisible(retry and true or false)
  panel:getChildById('playButton'):setVisible(play and true or false)
  panel:getChildById('restartButton'):setVisible(restart and true or false)
end

local function showPanel()
  if not alive(blocker) then
    blocker = g_ui.createWidget('ChaosUpdateBlocker', rootWidget)
  end
  if not alive(panel) then
    panel = g_ui.createWidget('ChaosUpdatePanel', rootWidget)
    panel:getChildById('retryButton').onClick = function() U.check() end
    panel:getChildById('playButton').onClick = function() U.dismiss() end
    panel:getChildById('restartButton').onClick = function() U.restart() end
  end
  blocker:raise()
  panel:raise()
  buttons(false, false, false)
end

local function hidePanel()
  if alive(panel) then panel:destroy() end
  if alive(blocker) then blocker:destroy() end
  panel, blocker = nil, nil
end

local function progress(percent, detail, note)
  if not alive(panel) then return end
  panel:getChildById('bar'):setPercent(math.max(0, math.min(100, math.floor(percent))))
  if detail then setText('detail', detail) end
  if note then setText('note', note) end
end

-- ---------------------------------------------------------------- phases

function U.blocking()
  return phase == 'checking' or phase == 'hashing' or phase == 'downloading' or phase == 'applying'
      or phase == 'restart' or phase == 'blocked' or phase == 'stopped'
end

function U.dismiss()
  if phase == 'blocked' then return end
  phase = 'done'
  hidePanel()
end

-- the update is in place and loads at the next start: the player closes the client and starts it again
local function manualRestart()
  setText('note', tr('Close the client and start it again to load the update.'))
  if alive(panel) then
    local b = panel:getChildById('restartButton')
    b:setText(tr('Close and start again'))
    b.onClick = function() g_app.exit() end
  end
end

function U.restart()
  phase = 'restart'
  result.restart = core.restartMode(g_app)
  if result.restart ~= 'restart' then
    -- an exe without base patch 0101: its g_app.restart left from inside this Lua call and aborted the client
    g_logger.info('updater: this client cannot restart itself safely; close it and start it again')
    return manualRestart()
  end
  g_logger.info('updater: restarting the client to load the update')
  local ok, err = pcall(function() g_app.restart() end)
  if not ok then
    g_logger.warning('updater: restart failed: ' .. tostring(err))
    manualRestart()
  end
end

-- the player may go on with the files they have (server unreachable, or the update failed)
local function fallback(title, why)
  local st = loadState()
  if manifestState then
    st.min_version = math.max(st.min_version or 0, manifestState.min_version or 0)
    st.min_package = math.max(st.min_package or 0, manifestState.min_package or 0)
  end
  local ok, verdict = core.offlineVerdict(cfg.required, st, cfg.package, cfg.baseline)
  result.fallback = ok and 'play' or 'blocked'
  g_logger.warning(('updater: %s (%s); %s'):format(title, tostring(why), ok and 'playing with the current files' or verdict))
  showPanel()
  setText('status', title)
  progress(0, why or '', ok and tr('You can play with the current files.') or verdict)
  if ok then
    phase = 'offline'
    buttons(true, true, false)
  else
    phase = 'blocked'
    buttons(true, false, false)
  end
end

-- ---------------------------------------------------------------- hashing (time-sliced, with a cache)

local function loadCache()
  local cache = {}
  for line in readText(CACHE):gmatch('[^\n]+') do
    local key, mtime, size, hash = line:match('^(.-)\t(%d+)\t(%d+)\t(%x+)$')
    if key then cache[key] = { mtime = tonumber(mtime), size = tonumber(size), hash = hash } end
  end
  return cache
end

local function saveCache(cache)
  local out = {}
  for key, c in pairs(cache) do
    out[#out + 1] = ('%s\t%d\t%d\t%s'):format(key, c.mtime, c.size, c.hash)
  end
  table.sort(out)
  writeText(CACHE, table.concat(out, '\n') .. '\n')
end

-- sha256 of a virtual path, from the cache when the real file has the same time and size
local function hashOf(cache, used, vpath)
  local size = g_resources.fileSize(vpath)
  if size < 0 then return nil end
  local key = g_resources.getRealDir(vpath) .. '|' .. vpath
  local mtime = g_resources.getFileTime(vpath) or 0
  local c = cache[key]
  if c and mtime > 0 and c.mtime == mtime and c.size == size then
    used[key] = c
    return c.hash
  end
  local h = g_resources.fileSha256(vpath)
  if h == '' then return nil end
  if mtime > 0 then used[key] = { mtime = mtime, size = size, hash = h } end
  return h
end

local function compareFiles(m, onDone)
  phase = 'hashing'
  setText('status', tr('Checking files'))
  local cache, used = loadCache(), {}
  local mounted = boot.mounted
  local plan = { download = {}, drop = {}, stale = {}, treeUsed = false }
  local i, n = 1, #m.files
  local function slice()
    hashEvent = nil
    local t0 = g_clock.millis()
    while i <= n and g_clock.millis() - t0 < HASH_SLICE_MS do
      local e = m.files[i]
      local treePath = '/' .. core.TREE .. '/' .. e.path
      local treeHash = g_resources.fileExists(treePath) and hashOf(cache, used, treePath) or nil
      local visible
      if not (mounted and treeHash) then visible = hashOf(cache, used, '/' .. e.path) end
      local what = core.decide(e, treeHash, visible, mounted)
      if what == 'download' then
        plan.download[#plan.download + 1] = e
      elseif what == 'drop' then
        plan.drop[#plan.drop + 1] = e.path
      elseif treeHash and not mounted and visible ~= e.sha256 then
        plan.treeUsed = true  -- right file in the tree, but this session does not see it yet
      end
      i = i + 1
    end
    progress(100 * (i - 1) / math.max(1, n), ('%d / %d files'):format(i - 1, n))
    if i <= n then
      hashEvent = scheduleEvent(slice, 1)
      return
    end
    saveCache(used)
    -- tree files no manifest names any more
    local listed = {}
    for _, e in ipairs(m.files) do listed[e.path] = true end
    local prefix = '/' .. core.TREE .. '/'
    if g_resources.directoryExists('/' .. core.TREE) then
      for _, f in ipairs(g_resources.listDirectoryFiles('/' .. core.TREE, true, false, true)) do
        local rel = f:sub(1, #prefix) == prefix and f:sub(#prefix + 1) or nil
        if rel and not listed[rel] then plan.stale[#plan.stale + 1] = rel end
      end
    end
    onDone(plan)
  end
  slice()
end

-- ---------------------------------------------------------------- download + apply

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
  rename = function(from, to) return g_resources.moveUpdateFile(from, to) end,
  later = later,
}

local applyIo = {
  move = function(from, to) return g_resources.moveUpdateFile(from, to) end,
  copy = function(from, to) return g_resources.copyFile('/' .. from, '/' .. to) end,
  remove = function(path) return g_resources.removeUpdateTree(path) end,
  mkdirFor = function(path) g_resources.makeDir('/' .. dirOf(path)) end,
  writeState = function(text) return writeText(core.STATE, text) end,
}

local function newState(m)
  return {
    version = m.version, min_version = m.min_version or 0, min_package = m.min_package or 0,
    package = boot.packageId, applied = os.date('!%Y-%m-%dT%H:%M:%SZ'),
  }
end

local function finishApplied(count, bytes, seconds, workers)
  phase = 'restart'
  result.applied = count
  setText('status', tr('Update applied'))
  progress(100, ('%d files, %s in %.1f s (%d parallel)'):format(count, core.formatBytes(bytes), seconds, workers),
    tr('Restarting the client...'))
  buttons(false, false, true)
  if core.restartMode(g_app) ~= 'restart' then
    result.restart = 'manual'
    return manualRestart()
  end
  later(2500, U.restart)
end

local function applyPlan(m, plan, blobs, stats, seconds, workers)
  phase = 'applying'
  setText('status', tr('Applying the update'))
  local ok, err = core.apply({ blobs = blobs, drop = plan.drop, stale = plan.stale }, applyIo, newState(m))
  if not ok then
    return fallback(tr('Update could not be applied'), err)
  end
  g_resources.removeUpdateTree(core.STAGING:sub(1, -2))
  g_logger.info(('updater: update %d applied: %d files to download (%s), %d removed, %.2f s with %d parallel'):format(
    m.version, #blobs, core.formatBytes(stats and stats.bytesTotal or 0), #plan.drop + #plan.stale, seconds or 0, workers or 0))
  finishApplied(#plan.download + #plan.drop + #plan.stale, stats and stats.bytesTotal or 0, seconds or 0, workers or 0)
end

local function download(m, plan)
  local blobs = core.blobsFor(plan.download)
  for _, b in ipairs(blobs) do b.url = core.blobUrl(cfg.manifest, m.files_url, b.sha) end
  local workers = core.workerCount(tonumber(g_settings.getValue('chaos-update-parallel')), m.parallel)
  phase = 'downloading'
  setText('status', tr('Downloading the update'))
  g_resources.makeDir('/' .. core.STAGING)
  local total = 0
  for _, b in ipairs(blobs) do total = total + b.size end
  local t0 = g_clock.millis()
  local lastBytes, lastT, speed = 0, t0, 0
  result.workers = workers
  job = core.download({
    blobs = blobs, workers = workers, io = downloadIo,
    onProgress = function(s)
      local now = g_clock.millis()
      if now - lastT >= 500 then
        speed = (s.bytesDone - lastBytes) * 1000 / (now - lastT)
        lastBytes, lastT = s.bytesDone, now
      end
      progress(s.bytesTotal > 0 and 100 * s.bytesDone / s.bytesTotal or 100,
        ('%d / %d files   %s / %s'):format(s.filesDone, s.filesTotal, core.formatBytes(s.bytesDone), core.formatBytes(s.bytesTotal)),
        ('%s/s   %d parallel'):format(core.formatBytes(math.max(0, speed)), workers))
    end,
    onDone = function(ok, err)
      job = nil
      local seconds = (g_clock.millis() - t0) / 1000
      result.seconds = seconds
      if not ok then
        if phase == 'stopped' then return end
        return fallback(tr('Update refused'), err)
      end
      g_logger.info(('updater: downloaded %d files (%s) in %.2f s with %d parallel'):format(
        #blobs, core.formatBytes(total), seconds, workers))
      applyPlan(m, plan, blobs, { bytesTotal = total }, seconds, workers)
    end,
  })
end

local function onManifest(r)
  if phase ~= 'checking' then return end
  if r.error and r.error ~= '' or r.status ~= 200 then
    return fallback(tr('Update server unreachable'), r.error ~= '' and r.error or ('HTTP ' .. tostring(r.status)))
  end
  local envelope, jerr = core.jsonDecode(r.body)
  if type(envelope) ~= 'table' then return fallback(tr('Update refused'), 'manifest is not valid JSON (' .. tostring(jerr) .. ')') end
  local payload, why = core.checkEnvelope(envelope, cfg.publicKey, function(key, msg, sig)
    return g_crypt.ed25519Verify(key, msg, sig)
  end)
  if not payload then
    result.refused = why
    return fallback(tr('Update refused'), why)
  end
  local m, perr = core.jsonDecode(payload)
  if type(m) ~= 'table' then return fallback(tr('Update refused'), 'payload is not valid JSON (' .. tostring(perr) .. ')') end
  local st = loadState()
  local valid, reason = core.validateManifest(m, st.version > 0 and st.version or nil)
  if not valid then
    result.refused = reason
    return fallback(tr('Update refused'), reason)
  end
  manifest = m
  manifestState = { min_version = m.min_version or 0, min_package = m.min_package or 0 }
  if (m.min_package or 0) > (cfg.package or 0) then
    st.min_package = math.max(st.min_package, m.min_package)
    saveState(st)
    phase = 'blocked'
    result.fallback = 'blocked'
    setText('status', tr('A new client download is required'))
    progress(0, cfg.download ~= '' and cfg.download or tr('Download the new client from the website.'),
      tr('The game files of this client are too old for the server.'))
    buttons(true, false, false)
    return
  end
  if core.olderThanPackage(m, cfg.baseline) then
    -- a package built after this update was published: its own files are newer, never put the older ones over them
    phase = 'uptodate'
    result.upToDate = cfg.baseline
    result.skipped = m.version
    g_logger.info(('updater: update %d is older than this client package (%d): not applied'):format(m.version, cfg.baseline))
    setText('status', tr('Your client is up to date'))
    progress(100, ('update %d, package %d'):format(m.version, cfg.baseline), '')
    later(2500, function() if phase == 'uptodate' then U.dismiss() end end)
    return
  end
  compareFiles(m, function(plan)
    if phase ~= 'hashing' then return end
    if #plan.download == 0 and #plan.drop == 0 and #plan.stale == 0 then
      local newSt = newState(m)
      newSt.status = 'ok'
      saveState(newSt)
      if plan.treeUsed then
        result.applied = 0
        return finishApplied(0, 0, 0, 0)
      end
      phase = 'uptodate'
      result.upToDate = m.version
      g_logger.info(('updater: up to date (update %d)'):format(m.version))
      setText('status', tr('Your client is up to date'))
      progress(100, ('update %d, %d files checked'):format(m.version, #m.files), '')
      later(2500, function() if phase == 'uptodate' then U.dismiss() end end)
      return
    end
    if #plan.download == 0 then
      return applyPlan(m, plan, {}, { bytesTotal = 0 }, 0, 0)
    end
    download(m, plan)
  end)
end

function U.check()
  if not cfg or (phase ~= 'idle' and phase ~= 'offline' and phase ~= 'blocked' and phase ~= 'done') then return end
  if job then job.cancel(); job = nil end
  result = {}
  manifestState = nil
  phase = 'checking'
  showPanel()
  setText('status', tr('Checking for updates'))
  progress(0, '', '')
  local url = cfg.manifest .. (cfg.manifest:find('?', 1, true) and '&' or '?') .. 't=' .. os.time()
  httpGet(url, {}, nil, onManifest)
end

-- the native checks against known vectors (signature_vectors.lua); returns "ok N" or the first failure
function U.selfTest()
  local V = dofile('/modules/client_chaos_updater/signature_vectors.lua')
  local function unhex(h) return (h:gsub('..', function(x) return string.char(tonumber(x, 16)) end)) end
  local n = 0
  for i, v in ipairs(V.rfc8032) do
    local msg = unhex(v[2])
    if not g_crypt.ed25519Verify(v[1], msg, v[3]) then return 'FAIL rfc8032 ' .. i end
    if g_crypt.ed25519Verify(v[1], msg .. 'x', v[3]) then return 'FAIL rfc8032 changed message ' .. i end
    n = n + 2
  end
  local m = V.manifest
  if not g_crypt.ed25519Verify(m.key, m.payload, m.signature) then return 'FAIL manifest vector' end
  if g_crypt.ed25519Verify(m.key, (m.payload:gsub('"version":1', '"version":2')), m.signature) then return 'FAIL tampered manifest' end
  if g_crypt.sha256Encode('abc', false) ~= V.sha256.abc then return 'FAIL sha256' end
  return 'ok ' .. (n + 3)
end

-- for the tests (devexec) and the terminal
function U.status()
  return { phase = phase, result = result, mounted = boot and boot.mounted, version = loadState().version,
           baseline = cfg and cfg.baseline or 0, restart = core.restartMode(g_app) }
end

-- ---------------------------------------------------------------- module

local function enabled(c)
  return type(c) == 'table' and type(c.manifest) == 'string' and c.manifest ~= ''
end

function U.init()
  g_ui.importStyle('updater')
  connect(g_http, { onGet = onGet, onGetProgress = onGetProgress })
  cfg = Services and Services.update
  boot = CHAOS_UPDATE_BOOT or { packageId = '', mounted = false }
  if not enabled(cfg) then return end
  if core.offByEnv(os.getenv) then
    g_logger.info('updater: off (' .. core.OFF_ENV .. ' is set): no update check')
    return
  end
  if not (g_crypt.ed25519Verify and g_resources.fileSha256 and g_resources.moveUpdateFile) then
    g_logger.warning('updater: this client build has no update support (base patch 0031)')
    return
  end
  cfg.package = tonumber(cfg.package) or 0
  cfg.baseline = core.baseline(cfg.baseline)
  cfg.download = cfg.download or ''
  if not cfg.manifest:find('^https://') then
    g_logger.warning('updater: the manifest URL is not HTTPS (tests only)')
  end
  if EnterGame and EnterGame.doLogin then
    origDoLogin = EnterGame.doLogin
    EnterGame.doLogin = function(...)
      if U.blocking() then return end
      return origDoLogin(...)
    end
  end
  phase = 'idle'
  U.check()
end

function U.terminate()
  phase = 'stopped'
  if hashEvent then removeEvent(hashEvent); hashEvent = nil end
  if job then job.cancel(); job = nil end
  for id in pairs(httpOps) do g_http.cancel(id) end
  httpOps = {}
  for ev in pairs(timers) do removeEvent(ev) end
  timers = {}
  disconnect(g_http, { onGet = onGet, onGetProgress = onGetProgress })
  if origDoLogin and EnterGame then EnterGame.doLogin = origDoLogin end
  origDoLogin = nil
  hidePanel()
end
