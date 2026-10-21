-- luajit updater_core_test.lua && lua5.3 updater_core_test.lua (from the repo root or this folder)
-- The signed updater without the client: path rules, envelope and manifest checks, the diff, the download pool
-- (bounded workers, largest first, ranged parts with resume, retries, hash check per file, nothing applied on
-- failure) and the apply step, against a fake HTTP server and an in-memory disk.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local C = dofile(dir .. 'updater_core.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- paths
for _, p in ipairs({ 'modules/game_x/x.lua', 'data/things/1098/Tibia.spr', 'data/fonts/Verdana Bold-11px.png',
                     'data/minimap/regions/63-(33253-31491-7)subarea.png', 'layouts/mobile/a.otui', 'mods/m/a+b,c.png' }) do
  eq(C.checkPath(p), true, 'accepted ' .. p)
end
local refused = {
  ['../init.lua'] = 'dot segment', ['modules/../init.lua'] = 'dot segment', ['/etc/passwd'] = 'absolute path',
  ['C:/x/y.lua'] = 'drive or stream name', ['modules\\x.lua'] = 'backslash', ['init.lua'] = 'not in a folder',
  ['bin/x.lua'] = 'root not allowed', ['modules/x/client.dll'] = 'native code is never updated',
  ['data/x/run.EXE'] = 'native code is never updated', ['modules/x/a.sh'] = 'native code is never updated',
  ['modules//x.lua'] = 'empty segment', ['modules/./x.lua'] = 'dot segment', ['modules/x/con.lua'] = 'device name',
  ['modules/x/ a.lua'] = 'space at an end', ['modules/x/a.'] = 'trailing dot', ['modules/x/a$b.lua'] = 'bad character',
  ['modules/x/'] = 'trailing slash', ['modules/x/\195\169.lua'] = 'bad character', [''] = 'empty path',
  ['MODULES/x.lua'] = 'root not allowed', ['modules/x/a\0.lua'] = 'bad character',
}
for p, why in pairs(refused) do
  local ok, reason = C.checkPath(p)
  eq(ok, nil, 'refused ' .. p); eq(reason, why, 'reason for ' .. p)
end
eq(select(2, C.checkPath(('a'):rep(201))), 'path too long', 'long path')

-- ---------------------------------------------------------------- JSON
do
  local J = C.jsonDecode
  local v = J(' {"a":[1,2.5,-3e2,true,false,null,"x\\"y\\\\z\\/\\n\\u00e9\\ud83d\\ude00"],"b":{},"c":[]} ')
  eq(v.a[1], 1, 'int'); eq(v.a[2], 2.5, 'float'); eq(v.a[3], -300, 'exp'); eq(v.a[4], true, 'true')
  eq(v.a[5], false, 'false'); eq(v.a[6], nil, 'null'); eq(v.a[7], 'x"y\\z/\n\195\169\240\159\152\128', 'escapes')
  eq(next(v.b), nil, 'empty object'); eq(#v.c, 0, 'empty array')
  for _, bad in ipairs({ '', '{', '{"a":}', '[1,]', '{"a":1}x', '"abc', '"a\1b"', '{a:1}', '[01x]', '"\\q"' }) do
    local r, err = J(bad)
    eq(r == nil and type(err) == 'string', true, 'refused json ' .. bad)
  end
  eq(select(2, J(('['):rep(40) .. (']'):rep(40))):match('^too deep') ~= nil, true, 'depth limit')
  -- a payload of 20000 entries, as an escaped string inside an envelope: linear time
  local entries = {}
  for i = 1, 20000 do
    entries[i] = ('{"path":"data/x/%05d.png","sha256":"%s","size":%d}'):format(i, ('ab'):rep(32), i)
  end
  local payload = '{"files":[' .. table.concat(entries, ',') .. '],"version":3}'
  local envText = '{"payload":"' .. payload:gsub('"', '\\"') .. '","signature":"x"}'
  local t0 = os.clock()
  local env2 = J(envText)
  local m2 = J(env2.payload)
  local dt = os.clock() - t0
  eq(env2.payload, payload, 'payload round trip'); eq(#m2.files, 20000, 'all entries'); eq(m2.files[20000].size, 20000, 'last entry')
  eq(dt < 5, true, ('20000 entries decoded in %.2f s'):format(dt))
end

-- ---------------------------------------------------------------- envelope and manifest
local KEY = ('ab'):rep(32)
local SIG = ('cd'):rep(64)
local function fakeVerify(key, msg, sig) return key == KEY and sig == SIG and msg == 'PAYLOAD' end
local env = { format = 'chaos-update-1', key = KEY, signature = SIG, payload = 'PAYLOAD' }
eq(C.checkEnvelope(env, KEY, fakeVerify), 'PAYLOAD', 'good envelope')
local function envWith(k, v) local e = {} for a, b in pairs(env) do e[a] = b end e[k] = v return e end
eq(select(2, C.checkEnvelope(envWith('signature', ('ce'):rep(64)), KEY, fakeVerify)), 'bad signature', 'bad signature')
eq(select(2, C.checkEnvelope(envWith('payload', 'PAYLOAd'), KEY, fakeVerify)), 'bad signature', 'changed payload')
eq(select(2, C.checkEnvelope(envWith('signature', ''), KEY, fakeVerify)), 'manifest is not signed', 'unsigned')
eq(select(2, C.checkEnvelope(envWith('key', ('11'):rep(32)), KEY, fakeVerify)), 'manifest signed with another key', 'other key')
eq(select(2, C.checkEnvelope(envWith('format', 'x'), KEY, fakeVerify)), 'unknown manifest format', 'format')
eq(select(2, C.checkEnvelope(env, '', fakeVerify)), 'no update key in this client', 'no key in client')
eq(select(2, C.checkEnvelope('x', KEY, fakeVerify)), 'manifest is not a JSON object', 'not an object')

local function sha(c) return (c):rep(64):sub(1, 64) end
local function manifest(files, version)
  return { format = 1, product = 'cinders-of-chaos', version = version or 5, min_version = 0, min_package = 0,
           parallel = 4, files_url = 'files/', files = files }
end
local good = manifest({ { path = 'modules/a/a.lua', sha256 = sha('a'), size = 10 } })
eq(C.validateManifest(good), true, 'valid manifest')
eq(C.validateManifest(good, 5), true, 'same version again')
eq(select(2, C.validateManifest(good, 6)), 'older manifest (5) than the one already applied (6)', 'rollback refused')
eq(select(2, C.validateManifest(manifest({ { path = '../x/a.lua', sha256 = sha('a'), size = 1 } }))),
   'refused path "../x/a.lua": dot segment', 'path in manifest')
eq(select(2, C.validateManifest(manifest({ { path = 'modules/a/a.lua', sha256 = sha('A'), size = 1 } }))),
   'bad sha256 for modules/a/a.lua', 'uppercase sha refused')
eq(select(2, C.validateManifest(manifest({ { path = 'modules/a/a.lua', sha256 = sha('a'), size = -1 } }))),
   'bad size for modules/a/a.lua', 'negative size')
eq(select(2, C.validateManifest(manifest({ { path = 'modules/a/a.lua', sha256 = sha('a'), size = 1 },
                                          { path = 'modules/a/A.lua', sha256 = sha('b'), size = 1 } }))),
   'duplicate path modules/a/A.lua', 'case-insensitive duplicate')
local other = manifest({}); other.product = 'x'
eq(select(2, C.validateManifest(other)), 'manifest of another product', 'product')
local fu = manifest({}); fu.files_url = 'file:///etc/'
eq(select(2, C.validateManifest(fu)), 'bad files_url', 'files_url scheme')
fu.files_url = '../../x/'
eq(select(2, C.validateManifest(fu)), 'bad files_url', 'files_url dots')

eq(C.blobUrl('https://site.example/updates/live/manifest.json?t=1', 'files/', sha('e')),
   'https://site.example/updates/live/files/ee/' .. sha('e'), 'blob url relative')
eq(C.blobUrl('https://a/m.json', 'https://cdn.example/f', sha('1')), 'https://cdn.example/f/11/' .. sha('1'), 'blob url absolute')
eq(C.workerCount(nil, 6), 6, 'manifest parallel'); eq(C.workerCount(2, 6), 2, 'setting wins')
eq(C.workerCount(nil, nil), 8, 'default parallel'); eq(C.workerCount(99, nil), 8, 'parallel capped')
eq(C.workerCount(0, 0), 8, 'zero means default')

-- ---------------------------------------------------------------- state, verdicts, diff
local st = C.parseState(C.formatState({ version = 7, min_version = 3, package = 'p1', status = 'ok' }))
eq(st.version, 7, 'state version'); eq(st.package, 'p1', 'state package'); eq(C.shouldMount(st, 'p1'), true, 'mount ok')
eq(C.shouldMount(st, 'p2'), false, 'other package not mounted')
st.status = 'applying'; eq(C.shouldMount(st, 'p1'), false, 'half applied not mounted')
eq(C.parseState('').version, 0, 'empty state')
eq(C.offlineVerdict(false, { version = 7, min_version = 3, min_package = 0 }, 1), true, 'offline playable')
eq(C.offlineVerdict(true, { version = 7, min_version = 0, min_package = 0 }, 1), false, 'required server')
eq(C.offlineVerdict(false, { version = 2, min_version = 3, min_package = 0 }, 1), false, 'below min version')
eq(C.offlineVerdict(false, { version = 7, min_version = 0, min_package = 2 }, 1), false, 'old package')
eq(C.offlineVerdict(false, { version = 0, min_version = 40, min_package = 0 }, 1, 47), true, 'baseline counts as applied')
eq(C.offlineVerdict(false, { version = 0, min_version = 48, min_package = 0 }, 1, 47), false, 'baseline below min version')

-- ---------------------------------------------------------------- package baseline (never downgrade), switches
eq(C.baseline(47), 47, 'baseline'); eq(C.baseline('47'), 47, 'baseline string'); eq(C.baseline(nil), 0, 'no baseline')
eq(C.baseline(-3), 0, 'negative baseline'); eq(C.baseline(4.5), 0, 'fractional baseline'); eq(C.baseline('x'), 0, 'bad baseline')
-- the incident: package winpkg-47 (baseline 47) found the live manifest of winpkg-46 and applied its older files
eq(C.olderThanPackage(manifest({}, 46), 47), true, 'older live manifest skipped')
eq(C.olderThanPackage(manifest({}, 47), 47), false, 'same version: compared, nothing to download')
eq(C.olderThanPackage(manifest({}, 48), 47), false, 'newer manifest applied')
eq(C.olderThanPackage(manifest({}, 1), 0), false, 'package without a baseline: old behaviour')
eq(C.olderThanPackage(manifest({}, 1), nil), false, 'no baseline field')
eq(C.offByEnv(function(k) return k == 'CHAOS_UPDATE_OFF' and '1' or nil end), true, 'env switch on')
eq(C.offByEnv(function() return nil end), false, 'env switch unset')
eq(C.offByEnv(function() return '' end), false, 'env switch empty')
eq(C.offByEnv(function() return '0' end), false, 'env switch 0')
eq(C.offByEnv(function() error('no env') end), false, 'getenv error')
eq(C.offByEnv(nil), false, 'no getenv')
eq(C.restartMode({ restart = function() end }), 'manual', 'old exe: no canRestart')
eq(C.restartMode({ restart = function() end, canRestart = function() return true end }), 'restart', 'patched exe')
eq(C.restartMode({ canRestart = function() return false end }), 'manual', 'engine says no')
eq(C.restartMode({ canRestart = function() error('x') end }), 'manual', 'canRestart error')
eq(C.restartMode(nil), 'manual', 'no g_app')

local e = { path = 'modules/a/a.lua', sha256 = sha('a'), size = 1 }
eq(C.decide(e, nil, sha('a'), false), 'keep', 'install file right')
eq(C.decide(e, nil, sha('b'), false), 'download', 'install file old')
eq(C.decide(e, nil, nil, false), 'download', 'missing file')
eq(C.decide(e, sha('a'), sha('b'), false), 'keep', 'tree file right')
eq(C.decide(e, sha('b'), sha('a'), false), 'drop', 'stale tree file over a right install file')
eq(C.decide(e, sha('b'), nil, true), 'download', 'stale tree file while mounted')

local blobs = C.blobsFor({ { path = 'data/s.spr', sha256 = sha('1'), size = 900 }, { path = 'modules/a.lua', sha256 = sha('2'), size = 5 },
                           { path = 'modules/b.lua', sha256 = sha('2'), size = 5 }, { path = 'data/d.dat', sha256 = sha('3'), size = 300 } })
eq(#blobs, 3, 'one blob per content'); eq(blobs[1].size, 900, 'largest first'); eq(blobs[3].size, 5, 'smallest last')
eq(#blobs[3].paths, 2, 'two paths share a blob')
eq(C.backoff(1), 500, 'backoff 1'); eq(C.backoff(3), 2000, 'backoff 3'); eq(C.backoff(10), 8000, 'backoff cap')
local a, b, t = C.parseContentRange('bytes 100-199/1000')
eq(a, 100, 'range start'); eq(b, 199, 'range end'); eq(t, 1000, 'range total')
eq(C.parseContentRange('items 1-2/3'), nil, 'bad range')
eq(C.header({ ['content-range'] = 'x' }, 'Content-Range'), 'x', 'header lookup ignores case')

-- ---------------------------------------------------------------- download pool (fake server and disk)

-- a deterministic stand-in for SHA-256 (64 hex digits)
local function fhash(s)
  local h1, h2 = 5381, 52711
  for i = 1, #s do
    local c = s:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 31 + c * 7) % 4294967296
  end
  return (('%08x%08x'):format(h1, h2)):rep(4)
end

local function newWorld(serverFiles, opts)
  opts = opts or {}
  local W = { disk = {}, pending = {}, timers = {}, maxActive = 0, active = 0, requests = {}, canceled = 0 }
  local nextId = 0
  W.io = {
    get = function(url, headers, onProgress, onDone)
      nextId = nextId + 1
      W.active = W.active + 1
      W.maxActive = math.max(W.maxActive, W.active)
      local req = { id = nextId, url = url, range = headers.Range, onProgress = onProgress, onDone = onDone }
      W.requests[#W.requests + 1] = req
      W.pending[#W.pending + 1] = req
      return nextId
    end,
    cancel = function(id)
      for i, r in ipairs(W.pending) do
        if r.id == id then table.remove(W.pending, i); W.active = W.active - 1; W.canceled = W.canceled + 1; return end
      end
    end,
    size = function(p) return W.disk[p] and #W.disk[p] or -1 end,
    read = function(p) return W.disk[p] end,
    write = function(p, d) W.disk[p] = d; return true end,
    append = function(p, d) W.disk[p] = (W.disk[p] or '') .. d; return true end,
    remove = function(p) W.disk[p] = nil; return true end,
    sha256 = function(p) return W.disk[p] and fhash(W.disk[p]) or '' end,
    rename = function(f, t2) if not W.disk[f] then return false end W.disk[t2] = W.disk[f]; W.disk[f] = nil; return true end,
    later = function(ms, fn) W.timers[#W.timers + 1] = { ms = ms, fn = fn } end,
  }
  -- answers the oldest pending request
  function W.serve()
    local req = table.remove(W.pending, 1)
    if not req then return false end
    W.active = W.active - 1
    local body = serverFiles[req.url]
    local fail = opts.fail and opts.fail(req)
    if fail then req.onDone({ status = 0, headers = {}, body = '', error = fail }); return true end
    if not body then req.onDone({ status = 404, headers = {}, body = '', error = 'HTTP error 404' }); return true end
    if opts.tamper then body = opts.tamper(req.url, body) end
    req.onProgress(50)
    if req.range and not opts.noRange then
      local s, e2 = req.range:match('bytes=(%d+)%-(%d+)')
      s, e2 = tonumber(s), tonumber(e2)
      req.onDone({ status = 206, headers = { ['Content-Range'] = ('bytes %d-%d/%d'):format(s, e2, #body) },
                   body = body:sub(s + 1, e2 + 1) })
      return true
    end
    req.onDone({ status = 200, headers = {}, body = body })
    return true
  end
  function W.drain()
    for _ = 1, 10000 do
      if not W.serve() then
        local t2 = table.remove(W.timers, 1)
        if not t2 then return end
        t2.fn()
      end
    end
  end
  return W
end

local function blobList(contents)
  local list, server = {}, {}
  for name, body in pairs(contents) do
    local h = fhash(body)
    list[#list + 1] = { path = 'data/' .. name, sha256 = h, size = #body }
    server['https://u/files/' .. h:sub(1, 2) .. '/' .. h] = body
  end
  local bl = C.blobsFor(list)
  for _, x in ipairs(bl) do x.url = C.blobUrl('https://u/manifest.json', 'files/', x.sha) end
  return bl, server
end

local big = ('S'):rep(25) .. ('p'):rep(20)    -- 45 bytes: 5 parts of 10 with chunk 10
local contents = { ['Tibia.spr'] = big, ['Tibia.dat'] = ('D'):rep(12), ['a.png'] = 'aaa', ['b.png'] = 'bbbb',
                   ['c.png'] = 'cc', ['d.png'] = 'ddddd', ['e.png'] = 'e' }

local function count(W, sha, range)
  local n = 0
  for _, r in ipairs(W.requests) do
    if r.url:sub(-64) == sha and (range == nil or r.range == range) then n = n + 1 end
  end
  return n
end

do -- bounded pool, largest first, the big file's parts in parallel, every file verified and staged, bytes add up
  local bl, server = blobList(contents)
  local W = newWorld(server)
  local done, lastStats = nil, nil
  local job = C.download({ blobs = bl, workers = 3, chunk = 10, io = W.io,
    onProgress = function(s) lastStats = { filesDone = s.filesDone, bytesDone = s.bytesDone, bytesTotal = s.bytesTotal } end,
    onDone = function(ok, err) done = { ok, err } end })
  eq(#W.pending, 3, 'three requests at once')
  eq(W.pending[1].url:sub(-64), fhash(big), 'largest file starts first')
  eq(W.pending[3].url:sub(-64), fhash(big), 'its parts run in parallel')
  eq(W.pending[1].range .. ' ' .. W.pending[2].range .. ' ' .. W.pending[3].range, 'bytes=0-9 bytes=10-19 bytes=20-29', 'part ranges')
  W.drain()
  eq(done[1], true, 'pool finished'); eq(W.maxActive, 3, 'never more than 3 requests')
  eq(lastStats.filesDone, 7, 'all files counted'); eq(lastStats.bytesDone, lastStats.bytesTotal, 'bytes add up')
  eq(lastStats.bytesTotal, 45 + 12 + 3 + 4 + 2 + 5 + 1, 'total bytes')
  for _, x in ipairs(bl) do eq(W.disk[C.STAGING .. x.sha], contents[x.paths[1]:sub(6)], 'staged ' .. x.paths[1]) end
  eq(count(W, fhash(big)), 5, 'five ranged requests for the 45-byte file')
  eq(count(W, fhash(('D'):rep(12))), 2, 'two for the 12-byte file')
  eq(count(W, fhash('aaa'), nil), 1, 'one plain request for a small file')
  local leftovers = 0
  for k in pairs(W.disk) do if k:find('%.c%d+$') or k:find('%.part$') then leftovers = leftovers + 1 end end
  eq(leftovers, 0, 'no part files left')
  eq(job.stats.active, 0, 'no request left')
end

do -- one worker: strictly one request at a time
  local bl, server = blobList(contents)
  local W = newWorld(server)
  local done
  C.download({ blobs = bl, workers = 1, chunk = 10, io = W.io, onDone = function(ok) done = ok end })
  W.drain()
  eq(done, true, 'single worker finished'); eq(W.maxActive, 1, 'single worker never overlaps')
end

do -- network errors: the failed part is retried with backoff, the parts already in are kept
  local bl, server = blobList({ ['Tibia.spr'] = big })
  local fails20 = 0
  local W = newWorld(server, { fail = function(req)
    if req.range == 'bytes=20-29' and fails20 < 3 then fails20 = fails20 + 1; return 'read error (connection reset)' end
  end })
  local done
  C.download({ blobs = bl, workers = 2, chunk = 10, io = W.io, onDone = function(ok, err) done = { ok, err } end })
  W.drain()
  eq(done[1], true, 'finished after retries')
  eq(count(W, fhash(big), 'bytes=20-29'), 4, 'failed part asked four times')
  eq(count(W, fhash(big), 'bytes=0-9'), 1, 'good part asked once')
  eq(count(W, fhash(big), 'bytes=40-44'), 1, 'last part asked once')
  eq(W.disk[C.STAGING .. bl[1].sha], big, 'file whole after retries')
end

do -- resume across runs: the parts an interrupted run finished are kept
  local bl, server = blobList({ ['Tibia.spr'] = big })
  local W = newWorld(server)
  local sha = bl[1].sha
  W.disk[C.STAGING .. sha .. '.c0'] = big:sub(1, 10)
  W.disk[C.STAGING .. sha .. '.c1'] = big:sub(11, 20)
  W.disk[C.STAGING .. sha .. '.c2'] = big:sub(21, 25)   -- cut short: fetched again
  local done, first
  C.download({ blobs = bl, workers = 2, chunk = 10, io = W.io, onDone = function(ok) done = ok end,
               onProgress = function(s) first = first or s.bytesDone end })
  eq(first, 20, 'progress starts at the kept parts')
  eq(W.pending[1].range, 'bytes=20-29', 'first request is the missing part')
  W.drain()
  eq(done, true, 'resumed download finished'); eq(W.disk[C.STAGING .. sha], big, 'resumed file whole')
  eq(count(W, sha), 3, 'only the missing parts were fetched')
end

do -- a server without range support answers 200 with the whole file
  local bl, server = blobList({ ['Tibia.spr'] = big })
  local W = newWorld(server, { noRange = true })
  local done
  C.download({ blobs = bl, workers = 2, chunk = 10, io = W.io, onDone = function(ok) done = ok end })
  W.drain()
  eq(done, true, 'no-range server ok'); eq(W.disk[C.STAGING .. bl[1].sha], big, 'whole file staged')
  eq(W.canceled, 1, 'the other parallel request is canceled')
end

do -- a tampered file is refused every time: the download fails, nothing is staged under its hash
  local bl, server = blobList({ ['Tibia.spr'] = big, ['a.png'] = 'aaa' })
  local W = newWorld(server, { tamper = function(url, body)
    if url:sub(-64) == fhash('aaa') then return 'aab' end
    return body
  end })
  local done
  C.download({ blobs = bl, workers = 2, chunk = 10, io = W.io, onDone = function(ok, err) done = { ok, err } end })
  W.drain()
  eq(done[1], false, 'tampered download fails')
  eq(done[2], 'data/a.png: hash mismatch (file refused)', 'reason names the file')
  eq(W.disk[C.STAGING .. fhash('aaa')], nil, 'tampered file not staged')
  eq(W.disk[C.STAGING .. fhash('aaa') .. '.part'], nil, 'tampered part removed')
  local tries = 0
  for _, r in ipairs(W.requests) do if r.url:sub(-64) == fhash('aaa') then tries = tries + 1 end end
  eq(tries, C.MAX_ATTEMPTS, 'tried MAX_ATTEMPTS times')
end

do -- a tampered large file (in parts): the joined file fails its hash, every retry too
  local bl, server = blobList({ ['Tibia.spr'] = big })
  local W = newWorld(server, { tamper = function(url, body) return body:sub(1, 30) .. 'X' .. body:sub(32) end })
  local done
  C.download({ blobs = bl, workers = 4, chunk = 10, io = W.io, onDone = function(ok, err) done = { ok, err } end })
  W.drain()
  eq(done[1], false, 'tampered large file fails'); eq(done[2], 'data/Tibia.spr: hash mismatch (file refused)', 'large file reason')
  local left = 0
  for _ in pairs(W.disk) do left = left + 1 end
  eq(left, 0, 'nothing of it left on disk')
  eq(count(W, bl[1].sha), 5 * C.MAX_ATTEMPTS, 'all parts fetched on each of the attempts')
end

do -- a file verified by an earlier, unfinished run is not downloaded again
  local bl, server = blobList({ ['a.png'] = 'aaa' })
  local W = newWorld(server)
  W.disk[C.STAGING .. fhash('aaa')] = 'aaa'
  local done
  C.download({ blobs = bl, workers = 2, io = W.io, onDone = function(ok) done = ok end })
  eq(done, true, 'already staged'); eq(#W.requests, 0, 'no request')
end

do -- a wrong partial answer (other range) counts as a failed attempt
  local bl, server = blobList({ ['Tibia.spr'] = big })
  local W = newWorld(server)
  local done
  C.download({ blobs = bl, workers = 1, chunk = 10, io = W.io, onDone = function(ok, err) done = { ok, err } end })
  local req = table.remove(W.pending, 1)
  W.active = W.active - 1
  req.onDone({ status = 206, headers = { ['Content-Range'] = 'bytes 5-14/45' }, body = big:sub(6, 15) })
  eq(#W.timers, 1, 'retry scheduled'); eq(W.timers[1].ms, 500, 'first backoff 500 ms')
  W.drain()
  eq(done[1], true, 'recovered after a bad partial answer')
end

do -- canceled: pending requests are canceled
  local bl, server = blobList(contents)
  local W = newWorld(server)
  local done
  local job = C.download({ blobs = bl, workers = 4, chunk = 10, io = W.io, onDone = function(ok, err) done = { ok, err } end })
  job.cancel()
  eq(done[1], false, 'cancel ends the pool'); eq(done[2], 'canceled', 'cancel reason'); eq(W.canceled, 4, 'requests canceled')
end

-- ---------------------------------------------------------------- apply
do
  local log, disk = {}, {}
  disk[C.STAGING .. 'S1'] = 'one'; disk[C.STAGING .. 'S2'] = 'two'
  local io = {
    move = function(f, t2) log[#log + 1] = 'move ' .. t2; disk[t2] = disk[f]; disk[f] = nil; return true end,
    copy = function(f, t2) log[#log + 1] = 'copy ' .. t2; disk[t2] = disk[f]; return true end,
    remove = function(p) log[#log + 1] = 'remove ' .. p; disk[p] = nil; return true end,
    mkdirFor = function() end,
    writeState = function(text) log[#log + 1] = 'state ' .. C.parseState(text).status; return true end,
  }
  local ok = C.apply({ blobs = { { sha = 'S1', paths = { 'modules/a/a.lua', 'modules/a/b.lua' } }, { sha = 'S2', paths = { 'data/x.png' } } },
                       drop = { 'modules/old/o.lua' }, stale = { 'mods/gone/g.lua' } }, io, { version = 9, package = 'p' })
  eq(ok, true, 'apply ok')
  eq(log[1], 'state applying', 'state says applying first')
  eq(log[#log], 'state ok', 'state ok last')
  eq(disk[C.TREE .. '/modules/a/a.lua'], 'one', 'first path moved'); eq(disk[C.TREE .. '/modules/a/b.lua'], 'one', 'shared blob copied')
  eq(disk[C.TREE .. '/data/x.png'], 'two', 'second blob')
  eq(table.concat(log, ';'):find('remove chaos_update/files/modules/old/o.lua', 1, true) ~= nil, true, 'dropped tree file removed')
  eq(table.concat(log, ';'):find('remove chaos_update/files/mods/gone/g.lua', 1, true) ~= nil, true, 'stale tree file removed')

  local log2 = {}
  local failIo = { move = function() return false end, copy = function() return true end, remove = function() end,
                   mkdirFor = function() end, writeState = function(text) log2[#log2 + 1] = C.parseState(text).status; return true end }
  local ok2, err2 = C.apply({ blobs = { { sha = 'S9', paths = { 'data/y.png' } } } }, failIo, { version = 9 })
  eq(ok2, nil, 'apply fails when a move fails'); eq(err2, 'cannot place data/y.png', 'apply failure reason')
  eq(log2[#log2], 'applying', 'a failed apply leaves the state at applying (the tree is not mounted)')
end

eq(C.formatBytes(1536), '2 KB', 'KB'); eq(C.formatBytes(3 * 1024 * 1024), '3.0 MB', 'MB')

print(('updater_core_test: %d checks, %s'):format(checks, fails == 0 and 'OK' or (fails .. ' FAILED')))
if fails > 0 then os.exit(1) end
