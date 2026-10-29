-- luajit cleanup_core_test.lua && lua5.3 cleanup_core_test.lua (from the repo root or this folder)
-- The clean start without the client: the keep-list, the decision (new package, new update, stale tree, half-applied
-- update), and the sweep on a fake folder holding the player's data, old update files, old skin copies and the client's
-- own files (which are never touched).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local C = dofile(dir .. 'cleanup_core.lua')
local U = dofile(dir .. 'updater_core.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- keep-list
for _, n in ipairs({ 'config.otml', 'Config.otml', 'config.otml.bak', 'characterdata', 'minimap.otmm', 'minimap.otmm.bak',
                     'minimap.otmm.1', 'bot', 'settings', 'settings.json', 'CindersOfChaos.log', 'CindersOfChaos.log.old',
                     'screenshots', 'chaos-prefs.json', 'chaos_clean_stamp.txt' }) do
  eq(C.keepName(n), true, 'kept ' .. n)
end
for _, n in ipairs({ 'chaos_update', 'chaos_skin_state.txt', 'images', 'data', 'modules', 'mods', 'layouts', 'downloads',
                     'sounds', 'skins', 'Tibia.spr', 'things', 'old.exe', 'config.lua' }) do
  eq(C.keepName(n), false, 'not kept ' .. n)
end
eq(C.keepName(''), true, 'empty name is never touched')
eq(C.safeName('a.png'), true, 'safe name')
for _, n in ipairs({ '', '.', '..', 'a/b', 'a\\b', 'C:x', 'a..b', 'a\nb' }) do eq(C.safeName(n), false, 'unsafe ' .. n) end

-- ---------------------------------------------------------------- the decision
local ID, OTHER = 'pkg-hash-1', 'pkg-hash-0'
local function tree(version, status, package)
  return { status = status or 'ok', package = package or ID, enc = U.ENCRYPTION, version = version }
end
local function decide(over)
  local ctx = { packageId = ID, stamp = C.parseStamp(C.formatStamp(ID, 5)), treeState = tree(5), treeExists = true, baseline = 4 }
  for k, v in pairs(over or {}) do ctx[k] = v end
  return C.decide(ctx)
end
local d = decide()
eq(d.run, false, 'same package and update: nothing to do'); eq(d.keepTree, true, 'tree kept'); eq(d.update, 5, 'update recorded')
d = decide({ stamp = C.parseStamp('') })
eq(d.run, true, 'no stamp yet: runs once'); eq(d.keepTree, true, 'a current tree survives the first run')
eq(d.reason, 'new client package', 'reason: package')
d = decide({ stamp = C.parseStamp(C.formatStamp(OTHER, 5)) })
eq(d.run, true, 'new package'); eq(d.keepTree, true, 'tree made for this package kept')
d = decide({ treeState = tree(5, 'ok', OTHER), stamp = C.parseStamp(C.formatStamp(OTHER, 5)) })
eq(d.run, true, 'tree of another package: runs'); eq(d.keepTree, false, 'tree of another package goes')
d = decide({ treeState = tree(6) })
eq(d.run, true, 'new in-game update'); eq(d.keepTree, true, 'the new tree stays'); eq(d.update, 6, 'new update recorded')
eq(d.reason, 'new update', 'reason: update')
d = decide({ treeState = tree(3), baseline = 4 })
eq(d.run, true, 'tree older than the package baseline'); eq(d.keepTree, false, 'stale tree goes')
d = decide({ treeState = tree(4), baseline = 4, stamp = C.parseStamp(C.formatStamp(ID, 4)) })
eq(d.run, false, 'tree equal to the baseline is current')
d = decide({ treeState = tree(7, 'applying'), stamp = C.parseStamp(C.formatStamp(ID, 5)) })
eq(d.run, false, 'a half-applied update is the updater\'s'); eq(d.keepTree, true, 'its tree is kept')
d = decide({ treeState = tree(7, 'applying', OTHER) })
eq(d.keepTree, false, 'half-applied update of another package goes')
d = decide({ treeState = {}, treeExists = false, stamp = C.parseStamp(C.formatStamp(ID, 0)) })
eq(d.run, false, 'no tree, cleaned for this package: nothing'); eq(d.update, 0, 'no update')
d = decide({ treeState = tree(5, 'ok', ID), treeExists = true, baseline = nil })
eq(d.run, false, 'no baseline known: version check off')
local s = C.parseStamp(C.formatStamp('abc', 12))
eq(s.package, 'abc', 'stamp package'); eq(s.update, 12, 'stamp update')
eq(C.parseStamp(nil).package, '', 'empty stamp'); eq(C.parseStamp('update=x').update, 0, 'bad update number')

-- ---------------------------------------------------------------- the sweep on a fake folder
-- files[path] = 'write' (in the write folder) or 'pack' (the client's own files); a path in both: write wins
local function world(entries)
  local w = { files = {}, deleted = {}, protectedDelete = {} }
  for path, where in pairs(entries) do w.files[path] = where end
  local function parentsOf(path)
    local out, cur = {}, ''
    for seg in path:gmatch('[^/]+') do
      out[#out + 1] = { dir = cur == '' and '/' or cur, name = seg }
      cur = cur .. '/' .. seg
    end
    return out
  end
  function w.isDir(path)
    local prefix = path .. '/'
    for p in pairs(w.files) do if p:sub(1, #prefix) == prefix then return true end end
    return false
  end
  function w.list(path)
    local names, seen = {}, {}
    for p in pairs(w.files) do
      for _, e in ipairs(parentsOf(p)) do
        if e.dir == path and not seen[e.name] then seen[e.name] = true; names[#names + 1] = e.name end
      end
    end
    table.sort(names)
    return names
  end
  -- a directory is in the write folder when any file under it is; a file by its own origin
  function w.inWrite(path)
    if w.files[path] then return w.files[path] == 'write' end
    local prefix = path .. '/'
    for p, where in pairs(w.files) do if p:sub(1, #prefix) == prefix and where == 'write' then return true end end
    return false
  end
  function w.delete(path)
    if w.files[path] then
      if w.files[path] ~= 'write' then w.protectedDelete[#w.protectedDelete + 1] = path; return false end
      w.files[path] = nil
      w.deleted[#w.deleted + 1] = path
      return true
    end
    return not w.isDir(path)   -- an empty (virtual) directory vanishes, a full one cannot be deleted
  end
  return w
end

local entries = {
  -- player data
  ['/config.otml'] = 'write', ['/config.otml.bak'] = 'write', ['/characterdata/12/hotkeys.otml'] = 'write',
  ['/characterdata/characters/alice/helper.json'] = 'write', ['/minimap.otmm'] = 'write', ['/bot/default/main.lua'] = 'write',
  ['/CindersOfChaos.log'] = 'write', ['/settings/clientoptions.json'] = 'write', ['/chaos_clean_stamp.txt'] = 'write',
  -- stale
  ['/chaos_update/state.txt'] = 'write', ['/chaos_update/files/data/things/1098/Tibia.spr'] = 'write',
  ['/chaos_update/staging/abc.part'] = 'write', ['/chaos_skin_state.txt'] = 'write',
  ['/images/chaos/skin/window.png'] = 'write', ['/modules/game_shaderfx/images/orb_ring_150.png'] = 'write',
  ['/data/images/game/buffs/haste.png'] = 'write', ['/downloads/old.zip'] = 'write', ['/old.exe'] = 'write',
  -- the client's own files, in some of the same folders
  ['/init.lua'] = 'pack', ['/modules/game_shaderfx/shaderfx.lua'] = 'pack', ['/data/images/game/buffs/new.png'] = 'pack',
  ['/data/images/ui/x.png'] = 'pack', ['/mods/a/b.lua'] = 'pack',
}
local w = world(entries)
local res = C.sweep(w, { keepTree = false })
local stillThere = {}
for p in pairs(w.files) do stillThere[p] = true end
for _, p in ipairs({ '/config.otml', '/config.otml.bak', '/characterdata/12/hotkeys.otml', '/characterdata/characters/alice/helper.json',
                     '/minimap.otmm', '/bot/default/main.lua', '/CindersOfChaos.log', '/settings/clientoptions.json',
                     '/chaos_clean_stamp.txt' }) do
  eq(stillThere[p], true, 'player data kept ' .. p)
end
for _, p in ipairs({ '/chaos_update/state.txt', '/chaos_update/files/data/things/1098/Tibia.spr', '/chaos_update/staging/abc.part',
                     '/chaos_skin_state.txt', '/images/chaos/skin/window.png', '/modules/game_shaderfx/images/orb_ring_150.png',
                     '/data/images/game/buffs/haste.png', '/downloads/old.zip', '/old.exe' }) do
  eq(stillThere[p], nil, 'stale removed ' .. p)
end
for _, p in ipairs({ '/init.lua', '/modules/game_shaderfx/shaderfx.lua', '/data/images/game/buffs/new.png', '/data/images/ui/x.png',
                     '/mods/a/b.lua' }) do
  eq(w.files[p], 'pack', 'client file untouched ' .. p)
end
eq(#w.protectedDelete, 0, 'no delete was even tried on a client file')
eq(res.removed >= 9, true, 'every stale file counted'); eq(res.failed, 0, 'no failure')
table.sort(res.kept)
eq(table.concat(res.kept, ','),
  'CindersOfChaos.log,bot,chaos_clean_stamp.txt,characterdata,config.otml,config.otml.bak,minimap.otmm,settings', 'kept list reported')
eq(w.isDir('/chaos_update'), false, 'the update folder is gone')

-- a current update tree stays when asked, the rest of the stale files go
w = world(entries)
C.sweep(w, { keepTree = true })
eq(w.files['/chaos_update/files/data/things/1098/Tibia.spr'], 'write', 'kept tree: files stay')
eq(w.files['/chaos_update/state.txt'], 'write', 'kept tree: state stays')
eq(w.files['/images/chaos/skin/window.png'], nil, 'kept tree: old skin copy goes')
eq(w.files['/data/images/game/buffs/haste.png'], nil, 'kept tree: old buff icon goes')
eq(w.files['/data/images/game/buffs/new.png'], 'pack', 'kept tree: client file stays')

-- a file that cannot be removed (in use) is counted, its folder stays, the others go
w = world(entries)
local realDelete = w.delete
w.delete = function(path) if path == '/downloads/old.zip' then return false end return realDelete(path) end
res = C.sweep(w, { keepTree = false })
eq(res.failed, 1, 'one failure'); eq(w.files['/downloads/old.zip'], 'write', 'the locked file stays')
eq(w.files['/old.exe'], nil, 'the others still go')

-- names that are not one plain segment are skipped, never joined into a path
w = world({ ['/ok.png'] = 'write' })
local listed = w.list
w.list = function(path) local t = listed(path); if path == '/' then t[#t + 1] = '..'; t[#t + 1] = 'a/b'; t[#t + 1] = 'C:' end return t end
local touched = {}
local del = w.delete
w.delete = function(path) touched[#touched + 1] = path; return del(path) end
C.sweep(w, { keepTree = false })
eq(table.concat(touched, ','), '/ok.png', 'only the plain name was touched')

-- a folder that exists only in the client's own files is never entered
w = world({ ['/modules/a.lua'] = 'pack' })
C.sweep(w, { keepTree = false })
eq(#w.protectedDelete, 0, 'client-only folder untouched')

-- the depth and count limits stop a runaway listing
local deep = {}
local path = ''
for i = 1, C.MAX_DEPTH + 5 do path = path .. '/d' .. i end
deep[path .. '/f'] = 'write'
w = world(deep)
res = C.sweep(w, { keepTree = false })
eq(res.stopped, true, 'depth limit reached')

print(('cleanup_core_test: %d checks, %d failures'):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
