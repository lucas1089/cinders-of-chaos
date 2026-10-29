-- luajit firststart_core_test.lua && lua5.3 firststart_core_test.lua (from the repo root or this folder)
-- The phone data core without the client: the manifest's phone list, the index of placed files, what to download, the
-- space check, the phases, the pruning on a new APK and the unpack step against a fake engine.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local U = dofile(dir .. '../client_chaos_updater/updater_core.lua')   -- sets the global ChaosUpdateCore
local C = dofile(dir .. 'firststart_core.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function sha(c) return (c:rep(64)):sub(1, 64) end
local function file(path, plain, size, blob)
  return { path = path, sha256 = sha(plain), size = size, blob = sha(blob), blob_size = size + U.BLOB_OVERHEAD }
end
local function manifest(files, android, version)
  return { format = 1, product = U.PRODUCT, version = version or 5, files = files, android = android }
end

-- ---------------------------------------------------------------- the phone list
local files = {
  file('data/things/1098/Tibia.dat', 'a', 100, 'A'), file('data/things/1098/Tibia.000.spr', 'b', 3000, 'B'),
  file('modules/game_x/x.lua', 'c', 10, 'C'), file('modules/game_x/copy.lua', 'c', 10, 'C'),
  file('layouts/mobile/styles/10-panels.otui', 'd', 5, 'D'), file('data/images/streamer/o.png', 'e', 7, 'E'),
}
local list = { 'data/things/1098/Tibia.dat', 'data/things/1098/Tibia.000.spr', 'modules/game_x/x.lua',
               'modules/game_x/copy.lua', 'data/images/streamer/o.png' }
local m = manifest(files, { version = 1, files = list })
local entries, why = C.androidEntries(m)
eq(#entries, 5, 'five phone files: ' .. tostring(why)); eq(entries[1].path, 'data/things/1098/Tibia.dat', 'list order kept')
eq(entries[3].blob, sha('C'), 'entries are the manifest entries (sizes and hashes stay signed)')
eq(select(2, C.androidEntries(manifest(files, nil))):match('no phone data') ~= nil, true, 'no section: reason')
eq(C.androidEntries(manifest(files, nil)), nil, 'no section: nil')
eq(C.androidEntries(manifest(files, 'x')), nil, 'section is not an object')
eq(C.androidEntries(manifest(files, { version = 2, files = list })), nil, 'unknown section version')
eq(C.androidEntries(manifest(files, { version = 1, files = {} })), nil, 'empty list')
eq(C.androidEntries(manifest(files, { version = 1 })), nil, 'no list')
eq(C.androidEntries(manifest(files, { version = 1, files = { 'modules/zz/z.lua' } })), nil, 'unknown file')
eq(C.androidEntries(manifest(files, { version = 1, files = { list[1], list[1] } })), nil, 'twice')
eq(C.androidEntries(manifest(files, { version = 1, files = { 'layouts/mobile/styles/10-panels.otui' } })), nil,
  'layouts/mobile is never on a phone')
eq(C.androidEntries(manifest(files, { version = 1, files = { 42 } })), nil, 'a path that is not a string')
eq(C.androidEntries(nil), nil, 'no manifest')

local things = C.restrict(entries, C.KEEP_DIR)
eq(#things, 2, 'restrict: the pair'); eq(things[2].path, 'data/things/1098/Tibia.000.spr', 'restrict keeps order')
local sc, name = C.scope({ version = 3 }, entries, 5)
eq(name, 'things', 'a manifest older than the APK: only the game data'); eq(#sc, 2, 'scope: the pair')
sc, name = C.scope({ version = 5 }, entries, 5)
eq(name, 'all', 'an equal manifest: everything'); eq(#sc, 5, 'scope: all')
sc, name = C.scope({ version = 1 }, entries, 0)
eq(name, 'all', 'no baseline: everything')

-- ---------------------------------------------------------------- the index
local ix = C.parseIndex(C.indexLine('data/a b.png', sha('a'), 12) .. C.indexLine('modules/x.lua', sha('b'), 3)
  .. C.indexLine('modules/x.lua', sha('c'), 4) .. 'garbage\n' .. 'p\tnothex\t3\n' .. 'q\t' .. sha('a') .. '\tx\n')
eq(ix['data/a b.png'].sha, sha('a'), 'index: path with a space'); eq(ix['data/a b.png'].size, 12, 'index: size')
eq(ix['modules/x.lua'].sha, sha('c'), 'index: the last line of a path wins'); eq(ix['modules/x.lua'].size, 4, 'index: last size')
eq(ix['p'], nil, 'index: bad hash ignored'); eq(ix['q'], nil, 'index: bad size ignored')
local text = C.formatIndex(ix)
eq(text, C.indexLine('data/a b.png', sha('a'), 12) .. C.indexLine('modules/x.lua', sha('c'), 4), 'index: sorted, one line each')
eq(C.parseIndex(text)['modules/x.lua'].size, 4, 'index: round trip')
eq(next(C.parseIndex(nil)), nil, 'index: nothing')

-- ---------------------------------------------------------------- decide
local e = file('modules/a/a.lua', 'a', 1, 'A')
eq(C.decide(e, sha('a'), nil), 'keep', 'the tree has the right file')
eq(C.decide(e, nil, sha('a')), 'keep', 'data.zip has the right file')
eq(C.decide(e, nil, nil), 'download', 'missing')
eq(C.decide(e, sha('z'), nil), 'download', 'the tree file is stale')
eq(C.decide(e, sha('z'), sha('a')), 'download', 'a stale tree file covers the right data.zip file: fetch it')
eq(C.decide(e, nil, sha('z')), 'download', 'data.zip has another file')
local stale = C.staleTree({ ['modules/old.lua'] = {}, ['modules/game_x/x.lua'] = {}, ['data/gone.png'] = {} }, entries)
eq(#stale, 2, 'two stale'); eq(stale[1], 'data/gone.png', 'stale sorted'); eq(stale[2], 'modules/old.lua', 'stale 2')

-- ---------------------------------------------------------------- sizes and space
local dl = { entries[1], entries[2], entries[3], entries[4] }
local s = C.summary(dl)
eq(s.files, 4, 'summary: files'); eq(s.blobs, 3, 'summary: x.lua and copy.lua share a blob')
eq(s.plainBytes, 100 + 3000 + 10 + 10, 'summary: plain bytes (each path)')
eq(s.blobBytes, 100 + 44 + 3000 + 44 + 10 + 44, 'summary: blob bytes (distinct blobs)')
eq(s.firstInstall, true, 'the pair is in it: first install')
eq(C.isFirstInstall({ entries[3] }), false, 'Lua only is no first install')
eq(C.needsConfirm(s), true, 'a first install asks')
eq(C.needsConfirm(C.summary({ entries[3] })), false, 'a small Lua update starts by itself')
eq(C.needsConfirm({ firstInstall = false, blobBytes = C.CONFIRM_BYTES }), true, 'a big update asks')
eq(C.needsConfirm({ firstInstall = false, blobBytes = C.CONFIRM_BYTES - 1 }), false, 'just under the limit')
local GB = 1024 ^ 3
eq(C.spaceNeeded(GB, 0), GB + C.SPACE_MARGIN, 'needed: data plus 0.5 GB')
eq(C.spaceNeeded(GB, 300 * 1024 * 1024), GB + C.SPACE_MARGIN - 300 * 1024 * 1024, 'needed: less what is staged')
eq(C.spaceNeeded(10, GB), 0, 'needed never below zero')
local ok, missing = C.spaceVerdict(2 * GB, GB + C.SPACE_MARGIN)
eq(ok, true, 'enough room'); eq(missing, 0, 'nothing missing')
ok, missing = C.spaceVerdict(GB, GB + C.SPACE_MARGIN)
eq(ok, false, 'not enough room'); eq(missing, C.SPACE_MARGIN, 'missing bytes')
eq((C.spaceVerdict(-1, GB)), true, 'unknown free space: go on'); eq((C.spaceVerdict(nil, GB)), true, 'no free space value: go on')
eq(C.spaceVerdict(GB + C.SPACE_MARGIN, GB + C.SPACE_MARGIN), true, 'exactly enough')

local CH = U.CHUNK
local big = { sha = sha('B'), size = CH * 2 + 5 }
local disk = {
  [C.STAGING .. sha('A')] = 144, [C.STAGING .. sha('B') .. '.c0'] = CH, [C.STAGING .. sha('B') .. '.c2'] = 5,
  [C.STAGING .. sha('C') .. '.part'] = 20,
}
local function size(p) return disk[p] or -1 end
eq(C.stagedBytes({ { sha = sha('A'), size = 144 }, big, { sha = sha('C'), size = 54 }, { sha = sha('D'), size = 9 } }, size),
  144 + CH + 5 + 20, 'staged: finished blob, finished parts, a half file, nothing')
eq(C.stagedBytes({}, size), 0, 'staged: nothing listed')

eq(C.workerCount(nil, nil), 4, 'phone workers: capped at 4'); eq(C.workerCount(8, 8), 4, 'phone workers: setting capped')
eq(C.workerCount(2, 8), 2, 'phone workers: the setting wins'); eq(C.workerCount(nil, 3), 3, 'phone workers: manifest')

-- ---------------------------------------------------------------- a new APK
local pr = C.prunePaths({ 'data', 'modules', 'mods', 'layouts', 'odd' }, { 'things', 'images', 'fonts' })
eq(table.concat(pr, ','), 'data/fonts,data/images,layouts,mods,modules,odd', 'prune: all but data/things')
eq(#C.prunePaths({}, {}), 0, 'prune: empty tree'); eq(#C.prunePaths({ 'data' }, { 'things' }), 0, 'prune: only the game data')
eq(#C.prunePaths(nil, nil), 0, 'prune: nil')

-- ---------------------------------------------------------------- phases
eq(C.nextPhase('checking', 'ready'), 'ready', 'checking -> ready')
eq(C.nextPhase('ready', 'start'), 'downloading', 'ready -> downloading')
eq(C.nextPhase('downloading', 'pause'), 'paused', 'downloading -> paused')
eq(C.nextPhase('paused', 'resume'), 'downloading', 'paused -> downloading')
eq(C.nextPhase('downloading', 'done'), 'unpacking', 'downloading -> unpacking')
eq(C.nextPhase('unpacking', 'done'), 'restart', 'unpacking -> restart')
eq(C.nextPhase('downloading', 'fail'), 'error', 'a failed download: error')
eq(C.nextPhase('error', 'retry'), 'checking', 'retry checks again')
eq(C.nextPhase('ready', 'retry'), 'checking', 'not enough space: retry checks again')
eq(C.nextPhase('offline', 'retry'), 'checking', 'offline: retry')
eq(C.nextPhase('blocked', 'retry'), 'checking', 'blocked: retry')
eq(C.nextPhase('paused', 'start'), nil, 'a paused download cannot start over'); eq(C.nextPhase('restart', 'done'), nil, 'restart is final')
eq(C.nextPhase('nowhere', 'start'), nil, 'unknown phase'); eq(C.nextPhase('uptodate', 'retry'), nil, 'up to date has no retry')
for _, ph in ipairs({ 'checking', 'ready', 'downloading', 'paused', 'unpacking', 'restart', 'error', 'blocked' }) do
  eq(C.blocksLogin(ph, false), true, 'blocks login: ' .. ph)
end
eq(C.blocksLogin('uptodate', true), false, 'up to date: login'); eq(C.blocksLogin('idle', false), false, 'idle: login')
eq(C.blocksLogin('offline', true), true, 'offline without game data: no login'); eq(C.blocksLogin('offline', false), false,
  'offline with game data: login')
eq(C.blocksLogin('stopped', true), false, 'stopped module never blocks')

-- ---------------------------------------------------------------- unpack
local function fakeEngine(over)
  local w = { staged = {}, tree = {}, index = {}, removed = {}, order = {}, queue = {} }
  w.io = {
    unpack = function(from, to)
      if over and over.fail == to then return '' end
      local blobSha = from:sub(#C.STAGING + 1)
      if not w.staged[blobSha] then return '' end
      w.tree[to] = true
      w.order[#w.order + 1] = to
      if over and over.wrong == to then return sha('9') end
      return w.staged[blobSha]
    end,
    remove = function(path) w.removed[#w.removed + 1] = path; w.tree[path] = nil; return true end,
    index = function(path, h, n) w.index[#w.index + 1] = path .. ':' .. h:sub(1, 1) .. ':' .. n end,
    later = function(ms, fn) w.queue[#w.queue + 1] = fn end,
  }
  function w.run() while #w.queue > 0 do table.remove(w.queue, 1)() end end
  return w
end
local blobsList = U.blobsFor({ entries[1], entries[2], entries[3], entries[4] })
local function stage(w) for _, b in ipairs(blobsList) do w.staged[b.sha] = b.plain end end

local w = fakeEngine()
stage(w)
local prog, doneOk, doneErr = {}, nil, nil
C.unpack({ blobs = blobsList, io = w.io, onProgress = function(p) prog[#prog + 1] = p end,
           onDone = function(ok, err) doneOk, doneErr = ok, err end })
eq(doneOk, nil, 'unpack: nothing happens before the first event')
w.run()
eq(doneOk, true, 'unpack: done ' .. tostring(doneErr))
eq(#w.order, 4, 'unpack: four files placed'); eq(#w.index, 4, 'unpack: four index lines')
eq(w.tree[C.TREE .. '/modules/game_x/x.lua'], true, 'unpack: into the tree')
eq(w.tree[C.TREE .. '/modules/game_x/copy.lua'], true, 'unpack: the second path of one blob')
eq(#prog, 4, 'unpack: progress per file'); eq(prog[4].filesDone, 4, 'unpack: files done'); eq(prog[4].bytesDone, prog[4].bytesTotal,
  'unpack: all bytes')
eq(prog[1].filesTotal, 4, 'unpack: files total')
local freed = {}
for _, p in ipairs(w.removed) do freed[p] = true end
eq(freed[C.STAGING .. sha('A')] and freed[C.STAGING .. sha('B')] and freed[C.STAGING .. sha('C')], true,
  'unpack: every staged blob removed after its last path')
eq(w.index[1]:match('^[^:]+:[^:]+:(%d+)$') ~= nil, true, 'unpack: index line has the plain size')
local cIdx = {}
for _, l in ipairs(w.index) do cIdx[#cIdx + 1] = l end
local joined = table.concat(cIdx, '|')
eq(joined:find('Tibia.000.spr:b:3000', 1, true) ~= nil, true, 'unpack: sprite shard indexed with its plain size')

-- a staged blob shared by two paths is kept until the second path is placed
w = fakeEngine(); stage(w)
local seen = {}
local oldUnpack = w.io.unpack
w.io.unpack = function(from, to)
  if to:find('copy.lua', 1, true) or to:find('x.lua', 1, true) then
    local present = false
    for _, p in ipairs(w.removed) do if p == from then present = true end end
    seen[to] = present
  end
  return oldUnpack(from, to)
end
C.unpack({ blobs = blobsList, io = w.io, onDone = function() end })
w.run()
eq(seen[C.TREE .. '/modules/game_x/x.lua'], false, 'unpack: the staged blob is still there for the first path')
eq(seen[C.TREE .. '/modules/game_x/copy.lua'], false, 'unpack: and for the second, which removes it afterwards')

-- a hash that is not the signed one
w = fakeEngine({ wrong = C.TREE .. '/modules/game_x/x.lua' }); stage(w)
doneOk, doneErr = nil, nil
C.unpack({ blobs = blobsList, io = w.io, onDone = function(ok, err) doneOk, doneErr = ok, err end })
w.run()
eq(doneOk, false, 'unpack: a wrong hash stops the run'); eq(doneErr:find('does not match the signed file') ~= nil, true, 'unpack: reason')
eq(w.tree[C.TREE .. '/modules/game_x/x.lua'], nil, 'unpack: the refused file is removed')

-- a file that cannot be written (disk full) or does not decrypt
w = fakeEngine({ fail = C.TREE .. '/data/things/1098/Tibia.000.spr' }); stage(w)
doneOk, doneErr = nil, nil
C.unpack({ blobs = blobsList, io = w.io, onDone = function(ok, err) doneOk, doneErr = ok, err end })
w.run()
eq(doneOk, false, 'unpack: a failed unpack stops the run'); eq(doneErr:find('cannot be unpacked') ~= nil, true, 'unpack: reason 2')
eq(#w.index < 4, true, 'unpack: files before the failure stay indexed, the rest does not')

-- cancel
w = fakeEngine(); stage(w)
doneOk, doneErr = nil, nil
local h = C.unpack({ blobs = blobsList, io = w.io, onDone = function(ok, err) doneOk, doneErr = ok, err end })
h.cancel()
w.run()
eq(doneOk, false, 'unpack: canceled'); eq(doneErr, 'canceled', 'unpack: cancel reason'); eq(#w.order, 0, 'unpack: nothing placed')

-- no blobs: done at once
w = fakeEngine()
doneOk = nil
C.unpack({ blobs = {}, io = w.io, onDone = function(ok) doneOk = ok end })
w.run()
eq(doneOk, true, 'unpack: empty list is done')

print(('firststart_core_test: %d checks, %s'):format(checks, fails == 0 and 'OK' or (fails .. ' FAILED')))
if fails > 0 then os.exit(1) end
