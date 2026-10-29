-- luajit boot_test.lua && lua5.3 boot_test.lua (from the repo root or this folder)
-- boot.lua and the Android branch of client_chaos_updater/bootstrap.lua against a fake g_resources: the phone data folder
-- is mounted only after a finished apply, an older APK's Lua and art in it are removed (the game data stays), a half
-- applied folder, CHAOS_UPDATE_OFF and an engine without the mount function mount nothing.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local realDofile = dofile
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local files, mounted, removed, written, logs, envOff, noMount
local function reset()
  files = {
    ['/chaos_update/android_state.txt'] = 'status=ok\nversion=7\npackage=PKG\nenc=chaos-blob-1\n',
    ['/chaos_update/android/data/things/1098/Tibia.dat'] = 'dat',
    ['/chaos_update/android/data/things/1098/Tibia.000.spr'] = 'spr',
    ['/chaos_update/android/data/images/x.png'] = 'old art',
    ['/chaos_update/android/modules/game_x/x.lua'] = 'old lua',
    ['/chaos_update/android/mods/m/m.lua'] = 'old mod',
    ['/chaos_update/android/layouts/classic/a.otui'] = 'old layout',
    ['/config.otml'] = 'x',
  }
  mounted, removed, written, logs, envOff, noMount = {}, {}, {}, {}, nil, false
end
local function children(p)
  local names, seen = {}, {}
  local pre = p .. '/'
  for k in pairs(files) do
    if k:sub(1, #pre) == pre then
      local n = k:sub(#pre + 1):match('^[^/]+')
      if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
  end
  table.sort(names)
  return names
end
g_resources = {
  fileExists = function(p) return files[p] ~= nil end,
  directoryExists = function(p) return #children(p) > 0 end,
  readFileContents = function(p) return files[p] or '' end,
  writeFileContents = function(p, t) files[p] = t; written[#written + 1] = p; return true end,
  listDirectoryFiles = function(p) return children(p) end,
  removeUpdateTree = function(rel)
    removed[#removed + 1] = rel
    local p, pre = '/' .. rel, '/' .. rel .. '/'
    files[p] = nil
    for k in pairs(files) do if k:sub(1, #pre) == pre then files[k] = nil end end
    return true
  end,
  mountDataFolder = function(rel) mounted[#mounted + 1] = rel; return true end,
}
g_logger = { info = function(m) logs[#logs + 1] = m end, warning = function(m) logs[#logs + 1] = 'WARN ' .. m end }
os.getenv = function(k) if k == 'CHAOS_UPDATE_OFF' then return envOff end return nil end
dofile = function(p)
  p = p:gsub('^/modules/client_chaos_updater/', dir .. '../client_chaos_updater/')
  p = p:gsub('^/modules/client_chaos_firststart/', dir)
  return realDofile(p)
end

local function boot(id)
  if noMount then g_resources.mountDataFolder = nil end
  realDofile(dir .. 'boot.lua')(id or 'PKG')
end
local function has(prefix)
  for _, l in ipairs(logs) do if l:find(prefix, 1, true) then return true end end
  return false
end

-- a finished apply of this package: mounted, nothing removed
reset(); boot()
eq(mounted[1], 'chaos_update/android', 'mounted the data folder'); eq(#removed, 0, 'nothing removed')
eq(CHAOS_UPDATE_BOOT.mounted, true, 'boot state: mounted'); eq(CHAOS_UPDATE_BOOT.packageId, 'PKG', 'boot state: package id')
eq(CHAOS_UPDATE_BOOT.state.version, 7, 'boot state: the saved state'); eq(CHAOS_UPDATE_BOOT.phone, true, 'boot state: phone')
eq(has('phone data: update 7 mounted'), true, 'logged')

-- a new APK: the old Lua and art go, the game data stays, the state follows the package
reset(); boot('NEWPKG')
eq(files['/chaos_update/android/modules/game_x/x.lua'], nil, 'old Lua removed'); eq(files['/chaos_update/android/mods/m/m.lua'], nil, 'old mods removed')
eq(files['/chaos_update/android/layouts/classic/a.otui'], nil, 'old layouts removed')
eq(files['/chaos_update/android/data/images/x.png'], nil, 'old art removed')
eq(files['/chaos_update/android/data/things/1098/Tibia.dat'], 'dat', 'the dat stays'); eq(files['/chaos_update/android/data/things/1098/Tibia.000.spr'], 'spr', 'the shards stay')
eq(files['/config.otml'], 'x', 'the player\'s settings are not touched')
eq(files['/chaos_update/android_state.txt']:find('package=NEWPKG', 1, true) ~= nil, true, 'state follows the package')
eq(files['/chaos_update/android_state.txt']:find('status=ok', 1, true) ~= nil, true, 'state keeps its status')
eq(mounted[1], 'chaos_update/android', 'mounted after the clean-up'); eq(has('new client package; 4 old folders removed'), true, 'logged')
for _, rel in ipairs(removed) do eq(rel:sub(1, 21), 'chaos_update/android/', 'only inside the data folder: ' .. rel) end
-- the next start with the same package removes nothing
removed = {}
boot('NEWPKG')
eq(#removed, 0, 'second start: nothing removed')

-- a half applied folder is not mounted
reset(); files['/chaos_update/android_state.txt'] = 'status=applying\nversion=8\npackage=PKG\n'
boot()
eq(#mounted, 0, 'applying: not mounted'); eq(CHAOS_UPDATE_BOOT.mounted, false, 'applying: boot state'); eq(has('data folder not used (applying)'), true, 'applying: logged')

-- no state at all: the first-start screen downloads the data
reset(); files['/chaos_update/android_state.txt'] = nil
boot()
eq(#mounted, 0, 'no state: not mounted'); eq(#removed, 0, 'no state: nothing removed'); eq(#written, 0, 'no state: nothing written')
eq(has('no game data yet'), true, 'no state: logged')

-- switches
reset(); envOff = '1'; boot()
eq(#mounted, 0, 'CHAOS_UPDATE_OFF: not mounted'); eq(#removed, 0, 'CHAOS_UPDATE_OFF: nothing removed')
reset(); noMount = true; boot()
eq(#mounted, 0, 'an engine without mountDataFolder: not mounted'); eq(has('WARN phone data: this client cannot mount'), true, 'and says so')
g_resources.mountDataFolder = function(rel) mounted[#mounted + 1] = rel; return false end
reset(); boot()
eq(CHAOS_UPDATE_BOOT.mounted, false, 'a mount that fails is not mounted'); eq(has('WARN phone data: the data folder could not be mounted'), true, 'and says so')
g_resources.mountDataFolder = function(rel) mounted[#mounted + 1] = rel; return true end

-- bootstrap.lua on a phone calls boot.lua and nothing of the desktop path
reset()
g_app = {
  getOs = function() return 'android' end, getBuildDate = function() return 'd' end, getBuildCommit = function() return 'c' end,
  getBuildArch = function() return 'arm64' end,
}
g_crypt = { sha256Encode = function(text) return 'PKG' end }
Services = { update = {} }
CHAOS_UPDATE_BOOT = nil
local sawDesktop = false
g_resources.mountUpdateOverlay = function() sawDesktop = true; return true end
realDofile(dir .. '../client_chaos_updater/bootstrap.lua')
eq(CHAOS_UPDATE_BOOT.phone, true, 'bootstrap on a phone runs the phone boot'); eq(CHAOS_UPDATE_BOOT.mounted, true, 'bootstrap on a phone: mounted')
eq(mounted[1], 'chaos_update/android', 'bootstrap on a phone: the data folder'); eq(sawDesktop, false, 'bootstrap on a phone: no encrypted overlay')
-- and on a desktop it does not
reset()
g_app.getOs = function() return 'windows' end
files['/chaos_update/state.txt'] = ''
CHAOS_UPDATE_BOOT = nil
realDofile(dir .. '../client_chaos_updater/bootstrap.lua')
eq(CHAOS_UPDATE_BOOT.phone, nil, 'bootstrap on a desktop: not the phone boot'); eq(#mounted, 0, 'bootstrap on a desktop: no data folder')

print(('boot_test: %d checks, %d failures'):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
