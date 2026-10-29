-- luajit cleanup_boot_test.lua && lua5.3 cleanup_boot_test.lua (from the repo root or this folder)
-- cleanup_boot.lua against a fake g_resources: a new package wipes the old update tree, old skin copies and downloads,
-- keeps the player's data and the client's own files, unmounts a stale mounted tree and writes the stamp; the next start
-- does nothing; CHAOS_CLEAN_OFF and an unknown write folder touch nothing.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local realDofile = dofile
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local files, deletedPack, unmounted, envOff
local function reset()
  files = {
    ['/config.otml'] = { 'write', 'layout=x' }, ['/characterdata/1/hotkeys.otml'] = { 'write', 'k' },
    ['/chaos_update/state.txt'] = { 'write', 'status=ok\npackage=OLD\nenc=chaos-blob-1\nversion=3\n' },
    ['/chaos_update/files/data/x.png'] = { 'write', 'x' }, ['/chaos_skin_state.txt'] = { 'write', 'skin=forge' },
    ['/modules/game_shaderfx/images/orb_ring_150.png'] = { 'write', 'old' }, ['/downloads/a.zip'] = { 'write', 'z' },
    ['/init.lua'] = { 'pack', '' }, ['/modules/game_shaderfx/shaderfx.lua'] = { 'pack', '' },
  }
  deletedPack, unmounted, envOff = 0, false, nil
end
local function isDir(p)
  local pre = p .. '/'
  for k in pairs(files) do if k:sub(1, #pre) == pre then return true end end
  return false
end
local function inWrite(p)
  if files[p] then return files[p][1] == 'write' end
  local pre = p .. '/'
  for k, v in pairs(files) do if k:sub(1, #pre) == pre and v[1] == 'write' then return true end end
  return false
end
g_resources = {
  getWriteDir = function() return '/home/u/.local/CindersOfChaos/' end,
  getRealDir = function(p) return inWrite(p) and '/home/u/.local/CindersOfChaos' or '/pack' end,
  fileExists = function(p) return files[p] ~= nil end,
  directoryExists = function(p) return isDir(p) end,
  readFileContents = function(p) return files[p] and files[p][2] or '' end,
  writeFileContents = function(p, t) files[p] = { 'write', t }; return true end,
  deleteFile = function(p)
    if files[p] then
      if files[p][1] ~= 'write' then deletedPack = deletedPack + 1; return false end
      files[p] = nil; return true
    end
    return not isDir(p)
  end,
  listDirectoryFiles = function(p)
    local names, seen = {}, {}
    local pre = p == '/' and '/' or p .. '/'
    for k in pairs(files) do
      if k:sub(1, #pre) == pre then
        local n = k:sub(#pre + 1):match('^[^/]+')
        if n and not seen[n] then seen[n] = true; names[#names + 1] = n end
      end
    end
    return names
  end,
  unmountUpdateOverlay = function() unmounted = true; return true end,
}
g_logger = { info = function() end, warning = function(m) print('WARN ' .. m) end }
os.getenv = function(k) if k == 'CHAOS_CLEAN_OFF' then return envOff end return nil end
dofile = function(p) return realDofile((p:gsub('^/modules/client_chaos_updater/', dir))) end

local function boot(over)
  CHAOS_UPDATE_BOOT = { packageId = 'NEW', mounted = true, state = {} }
  Services = { update = { baseline = 5 } }
  for k, v in pairs(over or {}) do CHAOS_UPDATE_BOOT[k] = v end
  realDofile(dir .. 'cleanup_boot.lua')
end

reset()
boot()
eq(ChaosCleanBoot.ran, true, 'ran on a new package')
eq(files['/config.otml'] ~= nil, true, 'settings kept'); eq(files['/characterdata/1/hotkeys.otml'] ~= nil, true, 'hotkeys kept')
eq(files['/chaos_update/files/data/x.png'], nil, 'old update tree removed')
eq(files['/chaos_skin_state.txt'], nil, 'skin state removed (the skin is copied fresh)')
eq(files['/modules/game_shaderfx/images/orb_ring_150.png'], nil, 'old orb ring copy removed')
eq(files['/downloads/a.zip'], nil, 'old download removed')
eq(files['/init.lua'][1], 'pack', 'client file untouched'); eq(deletedPack, 0, 'no delete tried on a client file')
eq(unmounted, true, 'stale tree unmounted'); eq(CHAOS_UPDATE_BOOT.mounted, false, 'boot state says so')
eq(files['/chaos_clean_stamp.txt'][2], 'package=NEW\nupdate=0\n', 'stamp written')
-- the next start does nothing
files['/downloads/b.zip'] = { 'write', 'z' }
boot({ mounted = false })
eq(ChaosCleanBoot.ran, false, 'second start: nothing to do'); eq(files['/downloads/b.zip'] ~= nil, true, 'untouched')

-- a current tree of this package survives and is not unmounted; a new update re-runs the sweep
reset()
files['/chaos_update/state.txt'][2] = 'status=ok\npackage=NEW\nenc=chaos-blob-1\nversion=6\n'
boot()
eq(ChaosCleanBoot.ran, true, 'ran'); eq(files['/chaos_update/files/data/x.png'] ~= nil, true, 'current tree kept')
eq(unmounted, false, 'current tree stays mounted'); eq(files['/chaos_clean_stamp.txt'][2], 'package=NEW\nupdate=6\n', 'update 6 stamped')
eq(files['/modules/game_shaderfx/images/orb_ring_150.png'], nil, 'old skin copy removed beside a current tree')
files['/chaos_update/state.txt'][2] = 'status=ok\npackage=NEW\nenc=chaos-blob-1\nversion=7\n'
files['/images/x.png'] = { 'write', 'old' }
boot()
eq(ChaosCleanBoot.ran, true, 'a new update cleans again'); eq(files['/images/x.png'], nil, 'old copy removed after the update')
eq(files['/chaos_update/files/data/x.png'] ~= nil, true, 'the new tree is kept')

-- a tree older than the package baseline goes
reset()
files['/chaos_update/state.txt'][2] = 'status=ok\npackage=NEW\nenc=chaos-blob-1\nversion=4\n'
files['/chaos_clean_stamp.txt'] = { 'write', 'package=NEW\nupdate=4\n' }
boot()
eq(ChaosCleanBoot.ran, true, 'stale tree: ran'); eq(files['/chaos_update/files/data/x.png'], nil, 'tree older than baseline removed')
eq(unmounted, true, 'and unmounted')

-- switches
reset(); envOff = '1'; boot()
eq(ChaosCleanBoot.ran, false, 'CHAOS_CLEAN_OFF'); eq(files['/downloads/a.zip'] ~= nil, true, 'nothing removed when off')
reset(); g_resources.getWriteDir = function() return '' end; boot()
eq(ChaosCleanBoot.ran, false, 'no write folder known'); eq(files['/downloads/a.zip'] ~= nil, true, 'nothing removed')

print(('cleanup_boot_test: %d checks, %d failures'):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
