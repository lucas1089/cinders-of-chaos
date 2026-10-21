-- Cinders of Chaos signed updater: the parts without client API (tests: updater_core_test.lua, plain Lua 5.1/5.3).
--
-- Used by bootstrap.lua (init.lua, before any module loads) and by updater.lua (the login-screen updater). The client
-- API comes in through small "io" tables, so the download pool and the apply step run here unchanged under the tests.
--
-- Manifest (client/MANIFEST.md "Signed updater"): manifest.json is an envelope
--   { "format": "chaos-update-1", "key": <public key hex>, "signature": <Ed25519 signature hex>, "payload": <string> }
-- where payload is the signed JSON text itself (the signature covers its exact bytes):
--   { "format": 1, "product": "cinders-of-chaos", "channel": "live", "version": N, "min_version": N, "min_package": N,
--     "parallel": N, "files_url": "files/", "created": "...", "encryption": "chaos-blob-1",
--     "files": [ { "path", "sha256", "size", "blob", "blob_size" }, ... ] }
-- Every file is served ENCRYPTED (client/tools/update_crypt.py, base patch 0103): "blob" is the SHA-256 of the
-- encrypted bytes and the file is fetched from <files_url>/<first two hex digits of blob>/<blob>; "sha256" and "size"
-- are the plaintext's. The signature covers both: a download is kept only when its bytes hash to "blob" and they
-- decrypt (GCM tag, in the engine: g_resources.updateBlobSha256) to "sha256". The blobs stay encrypted in the write dir
-- (chaos_update/files/); the engine decrypts them into memory at start (g_resources.mountUpdateOverlay). The server
-- only holds content-addressed ciphertext and the manifest is the one file that changes.

local M = {}
ChaosUpdateCore = M

M.FORMAT = 'chaos-update-1'
M.PRODUCT = 'cinders-of-chaos'
M.ROOT = 'chaos_update/'               -- in the write dir
M.TREE = 'chaos_update/files'          -- verified files, mounted at "/" by bootstrap.lua
M.STAGING = 'chaos_update/staging/'    -- downloads (<sha256>.part while incomplete, <sha256> once verified)
M.STATE = 'chaos_update/state.txt'
M.ALLOWED_ROOTS = { modules = true, mods = true, data = true, layouts = true }
-- never shipped by the updater: native code and anything a shell or the OS would run
M.DENIED_EXT = {
  exe = true, dll = true, so = true, dylib = true, bat = true, cmd = true, com = true, ps1 = true, sh = true,
  msi = true, scr = true, vbs = true, jar = true, app = true, sys = true, drv = true, cpl = true,
  lnk = true, reg = true, pif = true, hta = true, wsf = true, apk = true
}
M.WINDOWS_RESERVED = { con = true, prn = true, aux = true, nul = true }
for i = 1, 9 do M.WINDOWS_RESERVED['com' .. i] = true; M.WINDOWS_RESERVED['lpt' .. i] = true end
M.MAX_FILE_SIZE = 1024 * 1024 * 1024
M.MAX_FILES = 50000
M.DEFAULT_PARALLEL = 8
M.MAX_PARALLEL = 8
M.CHUNK = 8 * 1024 * 1024
M.MAX_ATTEMPTS = 5
-- encrypted update files (base patch 0103): the manifest's marker and the bytes a blob adds (header 28 + tag 16)
M.ENCRYPTION = 'chaos-blob-1'
M.BLOB_OVERHEAD = 44

-- ---------------------------------------------------------------- paths

-- A path the manifest may name: relative, "/"-separated, under modules/ mods/ data/ or layouts/, segments of
-- [A-Za-z0-9 ._()+,-] (no "..", no "." segment, no segment starting or ending with a space or ending with a dot,
-- no Windows device name), no native code. Returns true or nil, reason.
function M.checkPath(path)
  if type(path) ~= 'string' or path == '' then return nil, 'empty path' end
  if #path > 200 then return nil, 'path too long' end
  if path:find('\\', 1, true) then return nil, 'backslash' end
  if path:sub(1, 1) == '/' then return nil, 'absolute path' end
  if path:find(':', 1, true) then return nil, 'drive or stream name' end
  if path:sub(-1) == '/' then return nil, 'trailing slash' end
  local parts = {}
  for part in (path .. '/'):gmatch('([^/]*)/') do
    if part == '' then return nil, 'empty segment' end
    if part == '.' or part == '..' then return nil, 'dot segment' end
    if part:find('[^%w %._%(%)%+,%-]') then return nil, 'bad character' end
    if part:sub(1, 1) == ' ' or part:sub(-1) == ' ' then return nil, 'space at an end' end
    if part:sub(-1) == '.' then return nil, 'trailing dot' end
    local stem = part:lower():match('^([^%.]*)')
    if M.WINDOWS_RESERVED[stem] then return nil, 'device name' end
    parts[#parts + 1] = part
  end
  if #parts < 2 then return nil, 'not in a folder' end
  if not M.ALLOWED_ROOTS[parts[1]] then return nil, 'root not allowed' end
  local ext = parts[#parts]:lower():match('%.([^%.]+)$')
  if ext and M.DENIED_EXT[ext] then return nil, 'native code is never updated' end
  return true
end

function M.isHex(s, len)
  return type(s) == 'string' and #s == len and not s:find('[^0-9a-f]')
end

-- ---------------------------------------------------------------- JSON
-- A strict JSON decoder that stays linear on large input: the manifest's payload is a ~1 MB string with tens of
-- thousands of escaped quotes, which the general decoder of corelib builds by repeated concatenation (minutes and
-- gigabytes in the client). Strings are cut with string.find and joined once with table.concat.
-- Returns value or nil, error. Objects become tables, arrays sequences, null becomes nil.

local ESC = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function utf8char(c)
  if c < 0x80 then return string.char(c) end
  if c < 0x800 then return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64) end
  if c < 0x10000 then
    return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
  end
  return string.char(0xF0 + math.floor(c / 262144), 0x80 + math.floor(c / 4096) % 64, 0x80 + math.floor(c / 64) % 64,
    0x80 + c % 64)
end

function M.jsonDecode(str)
  if type(str) ~= 'string' then return nil, 'not a string' end
  local pos, depth = 1, 0
  local value

  local function fail(msg) error({ json = msg .. ' at ' .. pos }, 0) end
  local function skip() pos = str:find('[^ \t\r\n]', pos) or #str + 1 end

  local function parseString()
    pos = pos + 1
    local parts, n = {}, 0
    while true do
      local a = str:find('["\\%c]', pos)
      if not a then fail('unterminated string') end
      local c = str:sub(a, a)
      if a > pos then n = n + 1; parts[n] = str:sub(pos, a - 1) end
      if c == '"' then
        pos = a + 1
        return table.concat(parts)
      elseif c == '\\' then
        local e = str:sub(a + 1, a + 1)
        if e == 'u' then
          local hex = str:match('^%x%x%x%x', a + 2)
          if not hex then fail('bad \\u escape') end
          local code = tonumber(hex, 16)
          pos = a + 6
          if code >= 0xD800 and code <= 0xDBFF then
            local lo = str:match('^\\u(%x%x%x%x)', pos)
            if not lo then fail('lone surrogate') end
            code = 0x10000 + (code - 0xD800) * 1024 + (tonumber(lo, 16) - 0xDC00)
            pos = pos + 6
          end
          n = n + 1; parts[n] = utf8char(code)
        elseif ESC[e] then
          n = n + 1; parts[n] = ESC[e]
          pos = a + 2
        else
          fail('bad escape')
        end
      else
        fail('control character in string')
      end
    end
  end

  function value()
    skip()
    local c = str:sub(pos, pos)
    if c == '{' then
      depth = depth + 1
      if depth > 32 then fail('too deep') end
      pos = pos + 1
      local t = {}
      skip()
      if str:sub(pos, pos) == '}' then pos = pos + 1; depth = depth - 1; return t end
      while true do
        skip()
        if str:sub(pos, pos) ~= '"' then fail('expected a key') end
        local k = parseString()
        skip()
        if str:sub(pos, pos) ~= ':' then fail('expected :') end
        pos = pos + 1
        t[k] = value()
        skip()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == '}' then break end
        if d ~= ',' then fail('expected , or }') end
      end
      depth = depth - 1
      return t
    elseif c == '[' then
      depth = depth + 1
      if depth > 32 then fail('too deep') end
      pos = pos + 1
      local t, n = {}, 0
      skip()
      if str:sub(pos, pos) == ']' then pos = pos + 1; depth = depth - 1; return t end
      while true do
        n = n + 1
        t[n] = value()
        skip()
        local d = str:sub(pos, pos)
        pos = pos + 1
        if d == ']' then break end
        if d ~= ',' then fail('expected , or ]') end
      end
      depth = depth - 1
      return t
    elseif c == '"' then
      return parseString()
    elseif str:find('^true', pos) then pos = pos + 4; return true
    elseif str:find('^false', pos) then pos = pos + 5; return false
    elseif str:find('^null', pos) then pos = pos + 4; return nil
    end
    local num = str:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
    if not num or num == '' or not tonumber(num) then fail('unexpected character') end
    pos = pos + #num
    return tonumber(num)
  end

  local ok, res = pcall(function()
    local v = value()
    skip()
    if pos <= #str then fail('trailing garbage') end
    return v
  end)
  if ok then return res end
  if type(res) == 'table' and res.json then return nil, res.json end
  return nil, tostring(res)
end

-- ---------------------------------------------------------------- manifest

-- envelope: the decoded manifest.json. Returns payloadText or nil, reason. verify(publicKey, message, signature)
-- is g_crypt.ed25519Verify in the client.
function M.checkEnvelope(envelope, publicKey, verify)
  if type(envelope) ~= 'table' then return nil, 'manifest is not a JSON object' end
  if envelope.format ~= M.FORMAT then return nil, 'unknown manifest format' end
  if type(envelope.payload) ~= 'string' or envelope.payload == '' then return nil, 'manifest has no payload' end
  if not M.isHex(publicKey, 64) then return nil, 'no update key in this client' end
  if not M.isHex(envelope.signature, 128) then return nil, 'manifest is not signed' end
  if envelope.key ~= nil and envelope.key ~= publicKey then return nil, 'manifest signed with another key' end
  if not verify(publicKey, envelope.payload, envelope.signature) then return nil, 'bad signature' end
  return envelope.payload
end

local function isInt(v, min, max)
  return type(v) == 'number' and v == math.floor(v) and v >= (min or 0) and v <= (max or 2 ^ 53)
end

-- m: the decoded payload; lastVersion: the newest version this client accepted before (refuses a replayed older
-- manifest). Returns true or nil, reason.
function M.validateManifest(m, lastVersion)
  if type(m) ~= 'table' then return nil, 'payload is not a JSON object' end
  if m.format ~= 1 then return nil, 'unknown payload format' end
  if m.product ~= M.PRODUCT then return nil, 'manifest of another product' end
  if not isInt(m.version, 1) then return nil, 'bad version' end
  if lastVersion and m.version < lastVersion then
    return nil, ('older manifest (%d) than the one already applied (%d)'):format(m.version, lastVersion)
  end
  if m.min_version ~= nil and not isInt(m.min_version) then return nil, 'bad min_version' end
  if m.min_package ~= nil and not isInt(m.min_package) then return nil, 'bad min_package' end
  if m.parallel ~= nil and not isInt(m.parallel, 1, 64) then return nil, 'bad parallel' end
  if type(m.files_url) ~= 'string' or m.files_url == '' then return nil, 'no files_url' end
  if m.files_url:find('%.%.') or m.files_url:find('[%s\\]') then return nil, 'bad files_url' end
  if m.files_url:find('^%a[%w+.-]*:') and not m.files_url:find('^https?://') then return nil, 'bad files_url' end
  if m.encryption ~= M.ENCRYPTION then return nil, 'manifest is not encrypted (publish it again with the current tools)' end
  if type(m.files) ~= 'table' then return nil, 'no file list' end
  if #m.files > M.MAX_FILES then return nil, 'too many files' end
  local seen = {}
  for i, f in ipairs(m.files) do
    if type(f) ~= 'table' then return nil, 'bad file entry ' .. i end
    local ok, why = M.checkPath(f.path)
    if not ok then return nil, ('refused path %q: %s'):format(tostring(f.path), why) end
    local key = f.path:lower()
    if seen[key] then return nil, 'duplicate path ' .. f.path end
    seen[key] = true
    if not M.isHex(f.sha256, 64) then return nil, 'bad sha256 for ' .. f.path end
    if not isInt(f.size, 0, M.MAX_FILE_SIZE) then return nil, 'bad size for ' .. f.path end
    if not M.isHex(f.blob, 64) then return nil, 'bad blob for ' .. f.path end
    if f.blob_size ~= f.size + M.BLOB_OVERHEAD then return nil, 'bad blob_size for ' .. f.path end
  end
  return true
end

-- the URL a blob is fetched from: files_url relative to the manifest URL unless it is absolute
function M.blobUrl(manifestUrl, filesUrl, sha)
  local base
  if filesUrl:find('^https?://') then
    base = filesUrl
  else
    local dir = manifestUrl:gsub('[?#].*$', ''):match('^(.*/)') or ''
    base = dir .. filesUrl
  end
  if base:sub(-1) ~= '/' then base = base .. '/' end
  return base .. sha:sub(1, 2) .. '/' .. sha
end

-- workers: the client setting wins, then the manifest, then the default; always 1..MAX_PARALLEL (config.otml can be
-- edited by hand: text, NaN or a huge number fall back or are capped)
function M.workerCount(setting, manifestValue)
  local n = tonumber(setting)
  if not n or n ~= n or n < 1 then n = tonumber(manifestValue) end
  if not n or n ~= n or n < 1 then n = M.DEFAULT_PARALLEL end
  return math.max(1, math.min(M.MAX_PARALLEL, math.floor(n)))
end

-- ---------------------------------------------------------------- state (chaos_update/state.txt, key=value lines)

function M.parseState(text)
  local st = {}
  for line in tostring(text or ''):gmatch('[^\r\n]+') do
    local k, v = line:match('^([%w_]+)=(.*)$')
    if k then st[k] = v end
  end
  st.version = tonumber(st.version) or 0
  st.min_version = tonumber(st.min_version) or 0
  st.min_package = tonumber(st.min_package) or 0
  return st
end

function M.formatState(st)
  local keys, out = {}, {}
  for k in pairs(st) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = tostring(st[k]):gsub('[\r\n]', ' ')
    out[#out + 1] = k .. '=' .. v
  end
  return table.concat(out, '\n') .. '\n'
end

-- the bootstrap mounts the tree only when the last apply finished, for this client package, with encrypted files
function M.shouldMount(st, packageId)
  return st.status == 'ok' and st.package == packageId and st.enc == M.ENCRYPTION
end

-- a tree written before the update files were encrypted (plain files) is thrown away, never mounted or compared
function M.plainTreeLeft(st, treeExists)
  return treeExists == true and (type(st) ~= 'table' or st.enc ~= M.ENCRYPTION)
end

-- ---------------------------------------------------------------- hash cache (chaos_update/hashcache.txt)
-- "<realdir>|<path>\t<mtime>\t<size>\t<sha256>" lines after a "#stamp\t<stamp>" line. The pack's files all carry the
-- same ZIP date, so a hash is trusted only for the same stamp (this client package and update): a new exe or a new
-- update hashes everything once again.
function M.cacheStamp(packageId, st)
  st = type(st) == 'table' and st or {}
  return ('%s:%s:%s'):format(tostring(packageId or ''), tostring(st.version or 0), tostring(st.applied or ''))
end

function M.parseCache(text, stamp)
  local cache, first = {}, true
  for line in tostring(text or ''):gmatch('[^\n]+') do
    if first then
      first = false
      if line ~= '#stamp\t' .. stamp then return {} end
    else
      local key, mtime, size, hash = line:match('^(.-)\t(%d+)\t(%d+)\t(%x+)$')
      if key then cache[key] = { mtime = tonumber(mtime), size = tonumber(size), hash = hash } end
    end
  end
  return cache
end

function M.formatCache(cache, stamp)
  local out = {}
  for key, c in pairs(cache) do
    out[#out + 1] = ('%s\t%d\t%d\t%s'):format(key, c.mtime, c.size, c.hash)
  end
  table.sort(out)
  table.insert(out, 1, '#stamp\t' .. stamp)
  return table.concat(out, '\n') .. '\n'
end

-- may the player go on with the files they have? (offline, or the update failed)
-- required: Services.update.required; st: the saved state; package: this client's package number;
-- baseline: the update version of the package's own files (Services.update.baseline), counts as applied
function M.offlineVerdict(required, st, package, baseline)
  if required then return false, 'The update server is required to play.' end
  if (st.min_package or 0) > (package or 0) then return false, 'A new client download is required.' end
  if (st.min_version or 0) > math.max(st.version or 0, M.baseline(baseline)) then
    return false, 'An update is required to play.'
  end
  return true
end

-- ---------------------------------------------------------------- package baseline, switches, restart

-- Services.update.baseline: the update version this package's own files are (the release number the package was
-- built as, winpkg-N -> N; client/tools/set_update_config.py --baseline). 0 or missing: unknown (older packages).
function M.baseline(value)
  local n = tonumber(value)
  if not n or n ~= n or n < 0 or n ~= math.floor(n) then return 0 end
  return n
end

-- a manifest older than the package's own files is never applied: it would put older files over newer ones
-- (a package built after the live update was published). Equal is fine: the same content, nothing to download.
function M.olderThanPackage(m, baseline)
  local b = M.baseline(baseline)
  return b > 0 and type(m) == 'table' and type(m.version) == 'number' and m.version < b
end

-- the environment switch for test runs (CI start tests): CHAOS_UPDATE_OFF set to anything but "" / "0" turns the
-- updater off: no request to the update server, no update folder mounted, the package's own files only
M.OFF_ENV = 'CHAOS_UPDATE_OFF'
function M.offByEnv(getenv)
  if type(getenv) ~= 'function' then return false end
  local ok, v = pcall(getenv, M.OFF_ENV)
  return ok and type(v) == 'string' and v ~= '' and v ~= '0'
end

-- "restart": the engine restarts safely (base patch 0101 binds g_app.canRestart); "manual": an older exe, whose
-- g_app.restart left from inside the Lua call and could abort, so the player closes and starts the client
function M.restartMode(app)
  if type(app) ~= 'table' and type(app) ~= 'userdata' then return 'manual' end
  local okGet, fn = pcall(function() return app.canRestart end)
  if not okGet or type(fn) ~= 'function' then return 'manual' end
  local ok, yes = pcall(fn)
  return (ok and yes == true) and 'restart' or 'manual'
end

-- ---------------------------------------------------------------- diff

-- what to do with one manifest file. treeHash: sha256 of chaos_update/files/<path> as it is on disk, i.e. of the
-- ENCRYPTED blob, compared with entry.blob (nil when missing); visibleHash: sha256 of "/<path>" as the client sees it
-- (the pack's file, or the decrypted tree file when mounted), compared with entry.sha256; treeMounted: whether the
-- tree is mounted now.
--   "keep"     the client already sees the right file
--   "drop"     the install file is right but a stale tree file would cover it: remove the tree file
--   "download" fetch the blob
function M.decide(entry, treeHash, visibleHash, treeMounted)
  if treeHash then
    if treeHash == (entry.blob or entry.sha256) then return 'keep' end
    if not treeMounted and visibleHash == entry.sha256 then return 'drop' end
    return 'download'
  end
  if visibleHash == entry.sha256 then return 'keep' end
  return 'download'
end

-- blobs to fetch: one per encrypted blob (two paths with the same content download once), largest first.
-- b.sha / b.size: the encrypted bytes (what is fetched, hashed and stored); b.plain: the plaintext SHA-256 they must
-- decrypt to (entries without "blob" are the tests' plain stand-ins)
function M.blobsFor(entries)
  local by, list = {}, {}
  for _, e in ipairs(entries) do
    local sha = e.blob or e.sha256
    local b = by[sha]
    if not b then
      b = { sha = sha, size = e.blob_size or e.size, plain = e.blob and e.sha256 or nil, paths = {} }
      by[sha] = b
      list[#list + 1] = b
    end
    b.paths[#b.paths + 1] = e.path
  end
  table.sort(list, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.sha < b.sha
  end)
  return list
end

-- ---------------------------------------------------------------- HTTP helpers

function M.backoff(attempt)
  return math.min(500 * 2 ^ math.max(0, attempt - 1), 8000)
end

function M.header(headers, name)
  if type(headers) ~= 'table' then return nil end
  name = name:lower()
  for k, v in pairs(headers) do
    if tostring(k):lower() == name then return v end
  end
end

-- "bytes 100-199/1000" -> 100, 199, 1000 (total nil for "*")
function M.parseContentRange(value)
  if type(value) ~= 'string' then return nil end
  local a, b, total = value:match('^%s*bytes%s+(%d+)%-(%d+)/(%S+)%s*$')
  if not a then return nil end
  return tonumber(a), tonumber(b), tonumber(total)
end

-- ---------------------------------------------------------------- download pool
--
-- M.download(opts) fetches every blob into STAGING with a bounded pool of parallel requests.
--   opts.blobs     list from M.blobsFor (largest first), each with .url
--   opts.workers   how many requests run at once
--   opts.chunk     a blob larger than this is fetched in parts ("Range: bytes=a-b", one part per request); the
--                  parts of one blob run in parallel too, so the big Tibia.spr does not sit on one connection. Each
--                  finished part is a file (<sha>.c<i>): an interrupted run resumes with the parts it has. A server
--                  that ignores Range answers 200 with the whole file, which is taken as it is.
--   opts.io        get(url, headers, onProgress(percent), onDone(result)) -> id; cancel(id); size(path) -> bytes
--                  or -1; read(path); write(path, data); append(path, data); remove(path); sha256(path);
--                  plainSha256(path) (the SHA-256 the encrypted file decrypts to, "" when it does not decrypt:
--                  g_resources.updateBlobSha256); rename(from, to); later(ms, fn)
--   opts.onProgress(stats)  stats = { filesDone, filesTotal, bytesDone, bytesTotal, active }
--   opts.onDone(ok, err)
-- A blob's SHA-256 is checked as soon as its last byte is on disk, then what it decrypts to (b.plain); a mismatch
-- throws it away and counts as a failed attempt. A request or a blob failing opts.maxAttempts times stops the whole download; nothing is applied then.
function M.download(opts)
  local io = opts.io
  local chunk = opts.chunk or M.CHUNK
  local maxAttempts = opts.maxAttempts or M.MAX_ATTEMPTS
  local workers = math.max(1, opts.workers or M.DEFAULT_PARALLEL)
  local stats = { filesDone = 0, filesTotal = #opts.blobs, bytesDone = 0, bytesTotal = 0, active = 0 }
  local queue, active, waiting, finished = {}, {}, 0, false
  local doneBytes = 0
  local job = { stats = stats }
  local pump

  for _, b in ipairs(opts.blobs) do stats.bytesTotal = stats.bytesTotal + b.size end

  local function report()
    local bytes, n = doneBytes, 0
    for _, b in ipairs(opts.blobs) do
      if b.state and not b.state.done then bytes = bytes + b.state.have end
    end
    for item in pairs(active) do
      n = n + 1
      bytes = bytes + math.floor(item.len * (item.percent or 0) / 100)
    end
    stats.bytesDone = math.min(stats.bytesTotal, bytes)
    stats.active = n
    if opts.onProgress then opts.onProgress(stats) end
  end

  local function finish(ok, err)
    if finished then return end
    finished = true
    for item in pairs(active) do if item.req then io.cancel(item.req) end end
    active, queue = {}, {}
    report()
    opts.onDone(ok, err)
  end

  -- the items (requests) of one blob: one whole-file item, or one per part still missing
  local function itemsFor(bs)
    local b, items = bs.blob, {}
    if b.size <= chunk then
      items[1] = { bs = bs, first = nil, len = b.size, path = bs.part, attempts = 0 }
      return items
    end
    local i, first = 0, 0
    while first < b.size do
      local last = math.min(first + chunk, b.size) - 1
      local path = M.STAGING .. b.sha .. '.c' .. i
      local len = last - first + 1
      if io.size(path) == len then
        bs.have = bs.have + len
      else
        io.remove(path)
        items[#items + 1] = { bs = bs, index = i, first = first, last = last, len = len, path = path, attempts = 0 }
      end
      bs.parts = i + 1
      i, first = i + 1, last + 1
    end
    return items
  end

  local function enqueue(items, front)
    for k, it in ipairs(items) do
      it.bs.remaining = it.bs.remaining + 1
      if front then table.insert(queue, k, it) else queue[#queue + 1] = it end
    end
  end

  local function blobDone(bs)
    bs.done = true
    doneBytes = doneBytes + bs.blob.size
    stats.filesDone = stats.filesDone + 1
    report()
  end

  local function retryBlob(bs, why)
    bs.attempts = bs.attempts + 1
    if bs.attempts >= maxAttempts then
      return finish(false, ('%s: %s'):format(bs.blob.paths[1], why))
    end
    bs.have, bs.remaining = 0, 0
    waiting = waiting + 1
    io.later(M.backoff(bs.attempts), function()
      waiting = waiting - 1
      if finished then return end
      enqueue(itemsFor(bs), true)
      pump()
    end)
  end

  -- the signed plaintext hash of an encrypted blob (decrypted by the engine, GCM tag checked)
  local function plainOk(path, b)
    if not b.plain then return true end
    return type(io.plainSha256) == 'function' and io.plainSha256(path) == b.plain
  end

  local function verify(bs)
    if io.sha256(bs.part) ~= bs.blob.sha then
      io.remove(bs.part)
      return retryBlob(bs, 'hash mismatch (file refused)')
    end
    if not plainOk(bs.part, bs.blob) then
      io.remove(bs.part)
      return retryBlob(bs, 'does not decrypt to the signed file (refused)')
    end
    if not io.rename(bs.part, bs.final) then return finish(false, 'cannot write ' .. bs.final) end
    blobDone(bs)
  end

  -- every part is on disk: join them in order (one part per event, so the screen keeps drawing), then check the hash
  local function assemble(bs)
    io.remove(bs.part)
    waiting = waiting + 1
    local i = 0
    local function step()
      if finished then return end
      if i >= bs.parts then
        waiting = waiting - 1
        verify(bs)
        return pump()
      end
      local path = M.STAGING .. bs.blob.sha .. '.c' .. i
      local data = io.read(path)
      if not data or not io.append(bs.part, data) then return finish(false, 'cannot write ' .. bs.part) end
      io.remove(path)
      i = i + 1
      io.later(0, step)
    end
    step()
  end

  -- drops what is left of a blob (its whole body came in one answer)
  local function dropItems(bs)
    for k = #queue, 1, -1 do
      if queue[k].bs == bs then table.remove(queue, k) end
    end
    for item in pairs(active) do
      if item.bs == bs then
        if item.req then io.cancel(item.req) end
        active[item] = nil
      end
    end
    bs.remaining = 0
  end

  local function itemFailed(item, why)
    item.attempts = item.attempts + 1
    item.percent = 0
    if item.attempts >= maxAttempts then
      return finish(false, ('%s: %s'):format(item.bs.blob.paths[1], why))
    end
    waiting = waiting + 1
    io.later(M.backoff(item.attempts), function()
      waiting = waiting - 1
      if finished then return end
      table.insert(queue, 1, item)
      pump()
    end)
  end

  local function onResult(item, result)
    local bs, body = item.bs, result.body or ''
    if result.error and result.error ~= '' then return itemFailed(item, result.error) end
    if result.status == 206 and item.first then
      local a, b = M.parseContentRange(M.header(result.headers, 'Content-Range'))
      if a ~= item.first or b ~= item.last or #body ~= item.len then return itemFailed(item, 'bad partial response') end
      if not io.write(item.path, body) then return finish(false, 'cannot write ' .. item.path) end
      bs.have = bs.have + item.len
      bs.remaining = bs.remaining - 1
      if bs.remaining == 0 then assemble(bs) end
      return
    elseif result.status == 200 then
      if #body ~= bs.blob.size then return itemFailed(item, 'wrong size') end
      dropItems(bs)
      for i = 0, (bs.parts or 0) - 1 do io.remove(M.STAGING .. bs.blob.sha .. '.c' .. i) end
      bs.parts = nil
      if not io.write(bs.part, body) then return finish(false, 'cannot write ' .. bs.part) end
      bs.have = bs.blob.size
      return verify(bs)
    end
    return itemFailed(item, 'HTTP status ' .. tostring(result.status))
  end

  local function request(item)
    local headers = {}
    if item.first then headers['Range'] = ('bytes=%d-%d'):format(item.first, item.last) end
    item.percent = 0
    active[item] = true
    item.req = io.get(item.bs.blob.url, headers, function(percent)
      if finished or not active[item] then return end
      item.percent = percent
      report()
    end, function(result)
      if finished or not active[item] then return end
      active[item] = nil
      item.req = nil
      onResult(item, result)
      if not finished then
        report()
        pump()
      end
    end)
  end

  local pumping, again = false, false
  pump = function()
    if finished then return end
    if pumping then again = true; return end
    pumping = true
    repeat
      again = false
      local n = 0
      for _ in pairs(active) do n = n + 1 end
      while not finished and n < workers and #queue > 0 do
        request(table.remove(queue, 1))
        n = 0
        for _ in pairs(active) do n = n + 1 end
      end
    until not again or finished
    pumping = false
    if finished then return end
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    if n == 0 and #queue == 0 and waiting == 0 and stats.filesDone == stats.filesTotal then finish(true) end
  end

  function job.cancel() finish(false, 'canceled') end

  -- blobs already staged by an earlier run are kept; the rest is queued, largest first
  for _, b in ipairs(opts.blobs) do
    local bs = { blob = b, have = 0, remaining = 0, attempts = 0, done = false }
    bs.final = M.STAGING .. b.sha
    bs.part = bs.final .. '.part'
    b.state = bs
    if io.size(bs.final) == b.size and io.sha256(bs.final) == b.sha and plainOk(bs.final, b) then
      blobDone(bs)
    else
      io.remove(bs.part)
      local items = itemsFor(bs)
      if #items == 0 then assemble(bs) else enqueue(items, false) end
    end
    if finished then return job end
  end
  report()
  pump()
  return job
end

-- ---------------------------------------------------------------- apply
--
-- Moves the verified blobs into the tree in one go, after everything is downloaded. state.txt says "applying"
-- while files move, so a client stopped in the middle starts with its own install files (bootstrap.lua mounts only
-- an "ok" tree) and the next check finishes the job.
--   plan.blobs   blobs from M.blobsFor (already in STAGING)
--   plan.drop    tree paths to remove (stale copies)
--   plan.stale   tree paths that are in no manifest any more
--   io           move(from, to), copy(from, to), remove(path), writeState(text), mkdirFor(path)
--   state        the new state table (status is set here)
function M.apply(plan, io, state)
  local st = {}
  for k, v in pairs(state) do st[k] = v end
  st.status = 'applying'
  if not io.writeState(M.formatState(st)) then return nil, 'cannot write the update state' end
  for _, path in ipairs(plan.drop or {}) do io.remove(M.TREE .. '/' .. path) end
  for _, path in ipairs(plan.stale or {}) do io.remove(M.TREE .. '/' .. path) end
  for _, blob in ipairs(plan.blobs or {}) do
    local src = M.STAGING .. blob.sha
    for i = #blob.paths, 1, -1 do
      local dst = M.TREE .. '/' .. blob.paths[i]
      io.mkdirFor(dst)
      local ok
      if i == 1 then ok = io.move(src, dst) else ok = io.copy(src, dst) end
      if not ok then return nil, 'cannot place ' .. blob.paths[i] end
    end
  end
  st.status = 'ok'
  if not io.writeState(M.formatState(st)) then return nil, 'cannot write the update state' end
  return true
end

-- human sizes for the progress panel
function M.formatBytes(n)
  n = tonumber(n) or 0
  if n >= 1024 * 1024 * 1024 then return ('%.2f GB'):format(n / 1024 ^ 3) end
  if n >= 1024 * 1024 then return ('%.1f MB'):format(n / 1024 ^ 2) end
  if n >= 1024 then return ('%.0f KB'):format(n / 1024) end
  return ('%d B'):format(n)
end

return M
