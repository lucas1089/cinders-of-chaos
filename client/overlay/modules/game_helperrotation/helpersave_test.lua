-- luajit helpersave_test.lua && lua5.3 helpersave_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helpersave.lua')
local HS = ChaosHelperSave
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a tiny "JSON": key=value lines; anything else does not decode
local function encode(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. '=' .. tostring(t[k]) end
  return '{' .. table.concat(out, ';') .. '}'
end
local function decode(s)
  assert(s:sub(1, 1) == '{' and s:sub(-1) == '}', 'not json')
  local t = {}
  for k, v in s:sub(2, -2):gmatch('([%w_]+)=([^;]*)') do t[k] = tonumber(v) or v end
  return t
end
local function newFs()
  local files = {}
  local fs = { files = files, cutNextWrite = false }
  fs.exists = function(p) return files[p] ~= nil end
  fs.read = function(p) return files[p] end
  fs.write = function(p, text)
    if fs.cutNextWrite then fs.cutNextWrite = false files[p] = text:sub(1, 5) error('killed') end
    files[p] = text
  end
  fs.copy = function(a, b) files[b] = files[a] end
  fs.delete = function(p) files[p] = nil end
  return fs
end
local P = '/characterdata/characters/alice/helper.json'

-- read: missing, ok, broken with a backup, broken without one
local fs = newFs()
local v, status = HS.read(fs, P, decode)
eq(status, 'missing', 'no file: missing')
eq(HS.write(fs, P, encode({ heal = 70 }), decode), true, 'first write')
eq(fs.files[P .. '.tmp'], nil, 'temp copy removed after a good write')
eq(HS.write(fs, P, encode({ heal = 75 }), decode), true, 'second write')
eq(decode(fs.files[P .. '.bak']).heal, 70, 'the previous good file is the backup')
v, status = HS.read(fs, P, decode)
eq(status .. ':' .. v.heal, 'ok:75', 'reads the file')
fs.files[P] = '{heal=7'                      -- cut short (client killed on the death screen)
v, status = HS.read(fs, P, decode)
eq(status .. ':' .. tostring(v and v.heal), 'ok:70', 'a broken file: the backup is read')
eq(decode(fs.files[P]).heal, 70, 'the backup is put back in place')
eq(fs.files[P .. '.broken'], '{heal=7', 'the broken file is kept aside')
local fs2 = newFs()
fs2.files[P] = 'garbage'
v, status = HS.read(fs2, P, decode)
eq(status, 'broken', 'nothing readable: broken')
eq(fs2.files[P .. '.broken'], 'garbage', 'kept aside before any save')

-- a write killed half way leaves the old file readable
local fs3 = newFs()
HS.write(fs3, P, encode({ heal = 60 }), decode)
fs3.cutNextWrite = true
eq(HS.write(fs3, P, encode({ heal = 61 }), decode), false, 'a cut temp write fails')
eq(decode(fs3.files[P]).heal, 60, 'the file is untouched by a cut temp write')

-- the session: no save before a load, debounce, logout
local st = HS.newSession()
local KEY = '/characterdata/characters/alice'
eq(HS.canSave(st, KEY), false, 'no save before the load')
eq(HS.request(st, KEY, 0), nil, 'a change before the load is not saved')
HS.beginLoad(st)
HS.finishLoad(st, KEY, 'ok')
eq(HS.canSave(st, KEY), true, 'saves after the load')
eq(HS.canSave(st, '/characterdata/characters/bob'), false, 'never into another character')
eq(HS.request(st, KEY, 1000), 1500, 'due 500 ms after the change')
eq(HS.request(st, KEY, 1200), 1700, 'the last change wins')
eq(HS.isDue(st, 1600), false, 'not yet')
eq(HS.isDue(st, 1700), true, 'due')
HS.flushed(st)
eq(HS.isDue(st, 5000), false, 'flushed')

-- a death and relogin, as the helper runs it (base patch 0067): the helper's in-memory config, its saveSettings and
-- loadSettings with the module, the UI reset of logout that writes "off" values into the config
local disk = newFs()
local session = HS.newSession()
local config, now = nil, 0
local DEFAULTS = { heal = 80, potion = 50, autoEat = 0 }
local function copy(t) local c = {} for k, x in pairs(t) do c[k] = x end return c end
local function saveNow()
  if not HS.canSave(session, KEY) then return false end
  HS.flushed(session)
  return HS.write(disk, P, encode(config), decode)
end
local function change(k, x)
  config[k] = x
  HS.request(session, KEY, now)
end
local function tick(ms)
  now = now + ms
  if HS.isDue(session, now) then saveNow() end
end
local function login()
  HS.beginLoad(session)
  config = copy(DEFAULTS)               -- what a fresh client holds before the file is read
  tick(100)
  change('heal', 99)                    -- something (the UI, a level-change hook) touches the config early
  tick(1000)
  local value, status = HS.read(disk, P, decode)
  config = value or copy(DEFAULTS)
  HS.finishLoad(session, KEY, status)
end
local function logout()                 -- death -> Ok -> safe logout, or a plain logout
  saveNow()
  HS.endSession(session)
  config.heal, config.autoEat = 0, 0    -- the logout's UI reset
  change('potion', 0)
  tick(1000)
end

login()
eq(config.heal, 80, 'first login: defaults')
eq(disk.files[P], nil, 'the early change before the load wrote nothing')
change('heal', 70) change('potion', 40) change('autoEat', 1)
tick(600)
eq(decode(disk.files[P]).heal, 70, 'a change is saved 500 ms later (survives a crash)')
-- death: the death handler saves at once, then Ok logs out and in again
change('heal', 65)
saveNow()
logout()
eq(decode(disk.files[P]).heal, 65, 'the death save holds the last change')
eq(decode(disk.files[P]).potion, 40, 'the logout reset never reached the file')
login()
eq(config.heal .. '/' .. config.potion .. '/' .. config.autoEat, '65/40/1', 'after death and relogin: the setup is back')
-- a client killed on the death screen in the middle of the save, then restarted
change('heal', 66)
disk.cutNextWrite = true
saveNow()
HS.endSession(session)
login()
eq(config.heal, 65, 'killed during the save: the last good setup, never the defaults')
-- the file lost entirely: defaults, and nothing broken was overwritten
disk.files[P] = 'oops' disk.files[P .. '.bak'] = nil disk.files[P .. '.tmp'] = nil disk.files[P .. '.broken'] = nil
login()
eq(config.heal, 80, 'unreadable without a backup: defaults in memory')
eq(disk.files[P .. '.broken'], 'oops', 'the unreadable file kept aside')

if fails > 0 then error(fails .. ' failure(s)') end
print('helpersave_test: OK')
