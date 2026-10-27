-- luajit skin_core_test.lua (CI runs every client *_test.lua from the repo root, under LuaJIT and Lua 5.3)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local S = dofile(here .. 'skin_core.lua')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

-- the choice: unknown values fall back to classic
eq(S.normalize('forge'), 'forge', 'forge')
eq(S.normalize('  Abyss '), 'abyss', 'trim and case')
eq(S.normalize(nil), 'classic', 'nil')
eq(S.normalize(7), 'classic', 'number')
eq(S.normalize('bone'), 'classic', 'unknown')
eq(S.normalize(''), 'classic', 'empty')
eq(S.choose('forge', nil), 'forge', 'setting')
eq(S.choose('forge', 'abyss'), 'abyss', 'env wins')
eq(S.choose('forge', ''), 'forge', 'empty env ignored')
eq(S.choose('forge', 'nope'), 'classic', 'bad env')

-- path mapping
eq(S.sourceDir('classic'), nil, 'classic has no folder')
eq(S.sourceDir('forge'), '/skins/forge/', 'forge dir')
eq(S.sourceDir('x'), nil, 'unknown dir')
eq(S.mapPath('abyss', '/images/chaos/window.png'), '/skins/abyss/images/chaos/window.png', 'map')
eq(S.mapPath('classic', '/images/chaos/window.png'), nil, 'classic map')
eq(S.mapPath('forge', 'images/x.png'), nil, 'relative refused')
eq(S.mapPath('forge', '/a/../b.png'), nil, 'dotdot refused')
eq(S.manifestPath('forge'), '/skins/forge/manifest.lua', 'manifest path')

-- palettes: every skin has the same keys, all colours
local keys = {}
for k in pairs(S.PALETTES.classic) do keys[#keys + 1] = k end
for _, id in ipairs(S.SKINS) do
  for _, k in ipairs(keys) do
    local v = S.PALETTES[id][k]
    eq(type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') ~= nil, true, id .. '.' .. k)
  end
  for k in pairs(S.PALETTES[id]) do eq(S.PALETTES.classic[k] ~= nil, true, id .. ' extra key ' .. k) end
  eq(S.NAMES[id] ~= nil, true, 'name ' .. id)
end
eq(S.palette('zzz'), S.PALETTES.classic, 'unknown palette')
eq(S.PALETTES.forge.mana, '#2d68b8', 'forge mana')
eq(S.PALETTES.abyss.accent2, '#2fd0c0', 'abyss teal')

-- manifest checks
local m1 = { rev = 'r1', files = { 'images/chaos/window.png', 'images/chaos/button_normal.png', 'modules/a/b.png' } }
eq(S.checkManifest(m1), true, 'good manifest')
eq(S.checkManifest({ rev = 'r', files = { '/abs.png' } }), false, 'absolute')
eq(S.checkManifest({ rev = 'r', files = { 'a/../b.png' } }), false, 'dotdot')
eq(S.checkManifest({ rev = 'r', files = { 'a.png', 'a.png' } }), false, 'duplicate')
eq(S.checkManifest({ rev = '', files = { 'a.png' } }), false, 'no rev')
eq(S.checkManifest(nil), false, 'nil')

-- state round trip
local txt = S.formatState('forge', 'r1', m1.files)
local st = S.parseState(txt)
eq(st.skin, 'forge', 'state skin')
eq(st.rev, 'r1', 'state rev')
eq(#st.files, 3, 'state files')
eq(S.parseState(nil).skin, 'classic', 'empty state')
eq(S.parseState('skin=bone\nrev=x\nfile=a.png\n').skin, 'classic', 'unknown skin in state')
eq(#S.parseState('skin=bone\nrev=x\nfile=a.png\n').files, 0, 'classic state holds no files')
eq(#S.parseState('skin=forge\nrev=x\nfile=/etc/passwd\nfile=a/../b\nfile=ok.png\n').files, 1, 'bad paths in state dropped')

-- a mock write folder
local function newFs(sources)
  local fs = { files = {}, dirs = {}, log = {}, failOn = nil }
  for k, v in pairs(sources or {}) do fs.files[k] = v end
  function fs.read(p) if fs.files[p] == nil then error('no file') end return fs.files[p] end
  function fs.write(p, t) fs.files[p] = t return true end
  function fs.delete(p) fs.files[p] = nil fs.log[#fs.log + 1] = 'del ' .. p return true end
  function fs.mkdir(p) fs.dirs[p] = true return true end
  function fs.copy(from, to)
    if fs.failOn == to then return false end
    if fs.files[from] == nil then return false end
    fs.files[to] = fs.files[from]
    fs.log[#fs.log + 1] = 'cp ' .. to
    return true
  end
  fs.manifests = {}
  function fs.manifest(id) return fs.manifests[id] end
  return fs
end
local function sources(skin, m)
  local t = {}
  for _, f in ipairs(m.files) do t['/skins/' .. skin .. '/' .. f] = skin .. ':' .. f end
  return t
end

local fs = newFs(sources('forge', m1))
fs.manifests.forge = m1

-- classic on a clean folder: nothing happens
local r = S.sync(fs, 'classic')
eq(r.skin, 'classic', 'classic')
eq(r.changed, false, 'classic changes nothing')
eq(#fs.log, 0, 'classic writes nothing')

-- forge: copies the files and writes the state
r = S.sync(fs, 'forge')
eq(r.skin, 'forge', 'forge installed')
eq(r.copied, 3, 'three copied')
eq(fs.files['/images/chaos/window.png'], 'forge:images/chaos/window.png', 'shadow file')
eq(fs.dirs['/images/chaos'], true, 'dir made')
eq(S.parseState(fs.files[S.STATE]).rev, 'r1', 'state written')

-- same choice again: no work
local before = #fs.log
r = S.sync(fs, 'forge')
eq(r.changed, false, 'second start is a no-op')
eq(#fs.log, before, 'nothing copied twice')

-- new art (rev) replaces exactly the files
fs.manifests.forge = { rev = 'r2', files = m1.files }
r = S.sync(fs, 'forge')
eq(r.changed, true, 'new revision')
eq(r.copied, 3, 'recopied')

-- switch to abyss with other files: forge files go
local m2 = { rev = 'a1', files = { 'images/chaos/window.png', 'images/chaos/panel.png' } }
fs.manifests.abyss = m2
for k, v in pairs(sources('abyss', m2)) do fs.files[k] = v end
r = S.sync(fs, 'abyss')
eq(r.skin, 'abyss', 'abyss')
eq(fs.files['/images/chaos/window.png'], 'abyss:images/chaos/window.png', 'abyss window')
eq(fs.files['/images/chaos/button_normal.png'], nil, 'forge-only file removed')
eq(fs.files['/modules/a/b.png'], nil, 'forge module file removed')

-- back to classic: every shadow file is removed, the client's own files untouched
fs.files['/data/images/chaos/window.png'] = 'client own'
r = S.sync(fs, 'classic')
eq(r.skin, 'classic', 'back to classic')
eq(fs.files['/images/chaos/window.png'], nil, 'abyss window removed')
eq(fs.files['/images/chaos/panel.png'], nil, 'abyss panel removed')
eq(fs.files['/data/images/chaos/window.png'], 'client own', 'client files untouched')
eq(S.parseState(fs.files[S.STATE]).skin, 'classic', 'state classic')

-- unknown selection is classic
r = S.sync(fs, 'bone')
eq(r.skin, 'classic', 'unknown value')

-- a failed copy leaves classic and no half skin
local fs2 = newFs(sources('forge', m1))
fs2.manifests.forge = m1
fs2.failOn = '/modules/a/b.png'
r = S.sync(fs2, 'forge')
eq(r.skin, 'classic', 'failed copy: classic')
eq(r.failed, 1, 'one failure')
eq(fs2.files['/images/chaos/window.png'], nil, 'half skin undone')
eq(S.parseState(fs2.files[S.STATE]).skin, 'classic', 'state classic after failure')

-- a client without the skin folder runs classic
local fs3 = newFs({})
r = S.sync(fs3, 'forge')
eq(r.skin, 'classic', 'no manifest')
eq(r.error ~= nil, true, 'error told')
fs3.manifests.forge = { rev = 'x', files = { '/bad' } }
r = S.sync(fs3, 'forge')
eq(r.skin, 'classic', 'bad manifest')

print('skin_core_test: ' .. n .. ' checks ok')
