-- Phone data (O313): the parts of the first-start download without client API (tests: firststart_core_test.lua, plain
-- Lua 5.1/5.3). client/MANIFEST.md "Phone data", docs/ANDROID_CLIENT.md section 3.
--
-- An Android phone cannot hold chaos.pack in RAM, so the APK carries only the engine, the Lua and the UI (data.zip) and
-- fetches the game data (the sprite pair above all) on first start through the same signed manifest as the desktop
-- updater: client_chaos_updater's ChaosUpdateCore does the envelope, the paths, the download pool with ranged parts,
-- retries and resume, and the hash checks. What is different here:
--   * the manifest key "android" lists the files a phone needs (paths of "files"); layouts/mobile is never in it;
--   * a verified blob is not mounted from memory but UNPACKED (g_resources.unpackUpdateBlob, base patch 0167) into a
--     plain file of chaos_update/android/, which the engine mounts through PhysFS in front of data.zip (file-backed);
--   * chaos_update/android_index.txt records the SHA-256 of every file placed there (path, hash, size), so a start
--     compares the manifest with the folder without hashing a gigabyte on a phone;
--   * pause and resume: the download pool keeps finished parts and blobs in chaos_update/staging, and a blob already
--     unpacked is gone from there (the index says it is done).
-- ChaosUpdateCore (client_chaos_updater/updater_core.lua) must be loaded first.

local U = assert(ChaosUpdateCore, 'client_chaos_updater/updater_core.lua must be loaded first')

local M = {}
ChaosFirstStartCore = M

M.TREE = 'chaos_update/android'               -- plain files, mounted by boot.lua (g_resources.mountDataFolder)
M.STATE = 'chaos_update/android_state.txt'    -- key=value: status (applying|ok), version, package, applied
M.AUTOSTART = 'firststart_autostart'           -- emulator test marker (android-client.yml smoke_download): starts the download
M.INDEX = 'chaos_update/android_index.txt'    -- "<path>\t<sha256>\t<size>" per file placed in the tree
M.STAGING = U.STAGING
M.PROBE = 'data/things/1098/Tibia.dat'        -- the file that says the game data is there
M.KEEP_DIR = 'data/things/'                   -- survives a new APK; the rest of the tree is the old APK's Lua and art
M.MOBILE_PREFIX = 'layouts/mobile/'           -- the APK leaves it out on purpose; never on the phone list
M.SECTION_VERSION = 1
M.SPACE_MARGIN = 512 * 1024 * 1024            -- staging room on top of the data itself
M.CONFIRM_BYTES = 100 * 1024 * 1024           -- a smaller update starts by itself, a bigger one asks first
M.MAX_PARALLEL = 4                            -- requests at once on a phone (8 MB parts in memory)

-- ---------------------------------------------------------------- the manifest's phone list

-- m: the decoded and validated payload (U.validateManifest). Returns the file entries of the phone list in list order,
-- or nil, reason. A phone refuses the same things the publisher does (make_update_manifest.py check_android).
function M.androidEntries(m)
  local a = type(m) == 'table' and m.android or nil
  if a == nil then return nil, 'this update has no phone data (publish it again with the current tools)' end
  if type(a) ~= 'table' or a.version ~= M.SECTION_VERSION then return nil, 'unknown phone data section' end
  if type(a.files) ~= 'table' or #a.files == 0 then return nil, 'empty phone data list' end
  local by = {}
  for _, e in ipairs(m.files or {}) do by[e.path] = e end
  local out, seen = {}, {}
  for _, p in ipairs(a.files) do
    if type(p) ~= 'string' or not by[p] then return nil, ('phone data names a file the update does not have (%s)'):format(tostring(p)) end
    if seen[p] then return nil, 'phone data names a file twice (' .. p .. ')' end
    seen[p] = true
    if p:sub(1, #M.MOBILE_PREFIX) == M.MOBILE_PREFIX then return nil, 'phone data names ' .. p end
    out[#out + 1] = by[p]
  end
  return out
end

-- the entries under a prefix (an update older than the APK's own files only brings the sprite pair)
function M.restrict(entries, prefix)
  local out = {}
  for _, e in ipairs(entries) do
    if e.path:sub(1, #prefix) == prefix then out[#out + 1] = e end
  end
  return out
end

-- which entries this run looks at: all of them, or only the game data when the manifest is older than the APK
function M.scope(m, entries, baseline)
  if U.olderThanPackage(m, baseline) then return M.restrict(entries, M.KEEP_DIR), 'things' end
  return entries, 'all'
end

-- ---------------------------------------------------------------- the index of files placed in the tree

function M.indexLine(path, sha, size)
  return ('%s\t%s\t%d\n'):format(path, sha, size)
end

function M.parseIndex(text)
  local ix = {}
  for line in tostring(text or ''):gmatch('[^\r\n]+') do
    local path, sha, size = line:match('^(.-)\t(%x+)\t(%d+)$')
    if path and #sha == 64 then ix[path] = { sha = sha, size = tonumber(size) } end   -- the last line of a path wins
  end
  return ix
end

function M.formatIndex(ix)
  local paths = {}
  for p in pairs(ix) do paths[#paths + 1] = p end
  table.sort(paths)
  local out = {}
  for _, p in ipairs(paths) do out[#out + 1] = M.indexLine(p, ix[p].sha, ix[p].size) end
  return table.concat(out)
end

-- ---------------------------------------------------------------- what to download

-- entry: the manifest file; treeHash: the plaintext SHA-256 the index records for the file in the tree (nil: not in the
-- tree, or its size changed); visibleHash: SHA-256 of "/<path>" as the client sees it without the tree (data.zip).
--   "keep"      the phone already has the right file
--   "download"  fetch the blob
function M.decide(entry, treeHash, visibleHash)
  if treeHash == entry.sha256 then return 'keep' end
  if treeHash == nil and visibleHash == entry.sha256 then return 'keep' end
  return 'download'
end

-- tree files the update does not list any more (index paths, full scope only)
function M.staleTree(index, entries)
  local listed, out = {}, {}
  for _, e in ipairs(entries) do listed[e.path] = true end
  for p in pairs(index) do
    if not listed[p] then out[#out + 1] = p end
  end
  table.sort(out)
  return out
end

function M.isFirstInstall(download)
  for _, e in ipairs(download) do
    if e.path:sub(1, #M.KEEP_DIR) == M.KEEP_DIR then return true end
  end
  return false
end

-- download: the entries to fetch. Returns { files, blobs, plainBytes, blobBytes, firstInstall }.
function M.summary(download)
  local blobs = U.blobsFor(download)
  local s = { files = #download, blobs = #blobs, plainBytes = 0, blobBytes = 0, firstInstall = M.isFirstInstall(download) }
  for _, e in ipairs(download) do s.plainBytes = s.plainBytes + e.size end
  for _, b in ipairs(blobs) do s.blobBytes = s.blobBytes + b.size end
  return s
end

-- a small update starts by itself, a big one (the first install above all) asks first
function M.needsConfirm(s)
  return s.firstInstall or s.blobBytes >= M.CONFIRM_BYTES
end

-- bytes of the blobs already on disk (finished, a half file, finished parts), so a resumed run is not asked for the
-- space it already uses. size(path) is the byte size or -1.
function M.stagedBytes(blobs, size)
  local total = 0
  for _, b in ipairs(blobs) do
    local final = M.STAGING .. b.sha
    local n = size(final)
    if n == b.size then
      total = total + n
    else
      local part = size(final .. '.part')
      if part > 0 then total = total + part end
      for i = 0, math.ceil(b.size / U.CHUNK) - 1 do
        local c = size(final .. '.c' .. i)
        if c > 0 then total = total + c end
      end
    end
  end
  return total
end

-- the room a run needs: the data itself plus a staging margin, less what is already staged
function M.spaceNeeded(plainBytes, stagedBytes)
  return math.max(0, plainBytes + M.SPACE_MARGIN - (stagedBytes or 0))
end

-- free: bytes free (nil or negative: unknown, the run goes on). Returns ok, missingBytes.
function M.spaceVerdict(free, needed)
  if type(free) ~= 'number' or free < 0 then return true, 0 end
  if free >= needed then return true, 0 end
  return false, needed - free
end

-- parallel requests: the client setting wins, then the manifest, at most MAX_PARALLEL
function M.workerCount(setting, manifestValue)
  return math.min(M.MAX_PARALLEL, U.workerCount(setting, manifestValue))
end

-- ---------------------------------------------------------------- a new APK

-- The tree of an older APK holds that APK's Lua and art, which would hide the new data.zip. A new package keeps only the
-- game data (data/things): names are the top-level names of the tree and the names inside data/. Returns the paths,
-- relative to the tree, to remove.
function M.prunePaths(topNames, dataNames)
  local out = {}
  for _, n in ipairs(topNames or {}) do
    if n ~= 'data' then out[#out + 1] = n end
  end
  for _, n in ipairs(dataNames or {}) do
    if n ~= 'things' then out[#out + 1] = 'data/' .. n end
  end
  table.sort(out)
  return out
end

-- ---------------------------------------------------------------- the phases

M.TRANSITIONS = {
  checking = { ready = 'ready', start = 'downloading', fail = 'error', uptodate = 'uptodate', blocked = 'blocked',
               offline = 'offline' },
  ready = { start = 'downloading', fail = 'error', retry = 'checking' },
  downloading = { pause = 'paused', fail = 'error', done = 'unpacking' },
  paused = { resume = 'downloading' },
  unpacking = { fail = 'error', done = 'restart' },
  error = { retry = 'checking' },
  blocked = { retry = 'checking' },
  offline = { retry = 'checking' },
  uptodate = {},
  restart = {},
}

-- the phase after an event, or nil when the event does not apply
function M.nextPhase(phase, event)
  local t = M.TRANSITIONS[phase]
  return t and t[event] or nil
end

-- does the screen keep the player from logging in? needsData: the game data is missing
function M.blocksLogin(phase, needsData)
  if phase == 'idle' or phase == 'uptodate' or phase == 'stopped' then return false end
  if phase == 'offline' then return needsData == true end
  return true
end

-- ---------------------------------------------------------------- unpack

-- Turns the verified blobs in staging into plain files of the tree, one file per event so the screen keeps drawing.
--   opts.blobs   from U.blobsFor, downloaded and verified (b.sha, b.size, b.plain, b.paths)
--   opts.io      unpack(from, to) -> plaintext SHA-256 or "" (g_resources.unpackUpdateBlob); remove(path);
--                index(path, sha, size) (appends to the index file); later(ms, fn)
--   opts.onProgress({ filesDone, filesTotal, bytesDone, bytesTotal }), opts.onDone(ok, err)
-- A file is in the tree only after it decrypted (GCM tag) to the signed SHA-256; a mismatch removes it and stops the
-- run. The staged blob of a path is removed after its last path is placed, which frees its space at once.
function M.unpack(opts)
  local io = opts.io
  local jobs, total = {}, 0
  for _, b in ipairs(opts.blobs) do
    local plainSize = b.size - U.BLOB_OVERHEAD
    for i, p in ipairs(b.paths) do
      jobs[#jobs + 1] = { blob = b, path = p, last = i == #b.paths, plainSize = plainSize }
      total = total + plainSize
    end
  end
  local handle, canceled, i, done = {}, false, 0, 0
  function handle.cancel() canceled = true end
  local function step()
    if canceled then return opts.onDone(false, 'canceled') end
    i = i + 1
    local job = jobs[i]
    if not job then return opts.onDone(true) end
    local to = M.TREE .. '/' .. job.path
    local sha = io.unpack(M.STAGING .. job.blob.sha, to)
    if sha == '' or sha == nil then
      io.remove(to)
      return opts.onDone(false, job.path .. ': cannot be unpacked (disk full, or the file does not decrypt)')
    end
    if sha ~= job.blob.plain then
      io.remove(to)
      return opts.onDone(false, job.path .. ': does not match the signed file (refused)')
    end
    io.index(job.path, sha, job.plainSize)
    if job.last then io.remove(M.STAGING .. job.blob.sha) end
    done = done + job.plainSize
    if opts.onProgress then
      opts.onProgress({ filesDone = i, filesTotal = #jobs, bytesDone = done, bytesTotal = total })
    end
    io.later(0, step)
  end
  io.later(0, step)
  return handle
end

return M
