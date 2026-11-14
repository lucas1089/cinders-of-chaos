-- luajit effectopacity_glue_test.lua && lua5.3 effectopacity_glue_test.lua (CI runs it from the repo root)
-- effectopacity.lua on a fake engine: the one-time migration of the old values (through the settings module when it has the option,
-- straight to g_settings and the alphas when not), the warning ids handed to the engine, hello {need} at the game start and when
-- a slider moves (only while the two values differ, and never without the engine's markEffectSources), the marks message handed
-- to the engine as source 1, bad messages ignored, terminate telling the server to stop.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'effectopacitylogic.lua')
local L = EffectOpacityLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- a minimal json: encode a flat table with string / number / boolean values, decode what encode wrote
local function encode(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    parts[#parts + 1] = string.format('"%s":%s', k, type(v) == 'string' and ('"' .. v .. '"') or tostring(v))
  end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- the world of one run
local function newWorld(opts)
  opts = opts or {}
  local w = { store = {}, sent = {}, marked = {}, exempt = {}, alphas = {}, online = opts.online ~= false, applied = {} }
  for k, v in pairs(opts.store or {}) do w.store[k] = v end
  g_logger = { warning = function(t) w.warned = t end }
  json = { encode = encode }
  g_settings = {
    exists = function(k) return w.store[k] ~= nil end,
    getNumber = function(k) return w.store[k] end,
    getBoolean = function(k) return w.store[k] == true end,
    set = function(k, v) w.store[k] = v end,
  }
  local protocol = { sendExtendedOpcode = function(_, op, buf) w.sent[#w.sent + 1] = { op = op, buf = buf } end }
  g_game = {
    isOnline = function() return w.online end,
    getProtocolGame = function() return protocol end,
  }
  g_client = {
    setEffectAlpha = function(v) w.alphas.own = v end,
    setOtherPlayerSpellEffectAlpha = function(v) w.alphas.other = v end,
    setEffectAlphaExempt = function(id, on) w.exempt[id] = on end,
    clearEffectAlphaExempt = function() w.exempt = {} end,
  }
  if opts.marks ~= false then
    g_client.markEffectSources = function(source, x, y, z, flat)
      w.marked[#w.marked + 1] = { source = source, x = x, y = y, z = z, n = #flat }
      return #flat / 4
    end
  end
  ProtocolGame = {
    registerExtendedJSONOpcode = function(op, fn) w.opcode, w.handler = op, fn end,
    unregisterExtendedJSONOpcode = function(op) w.unregistered = op end,
  }
  function connect(_, t) w.game = t end
  function disconnect() w.disconnected = true end
  local opt = {}
  if opts.settingsModule then
    opt = {
      GameOptions = {
        getDataSet = function(_, key) return (key == 'opacityEffects' or key == 'opacityOtherEffects') and {} or nil end,
        setOption = function(_, key, v)
          w.store[key] = v
          w.applied[#w.applied + 1] = key .. '=' .. v
        end,
      },
    }
  end
  modules = { client_settings = opt }
  -- the module's globals are its own: a fresh environment per run
  local env = setmetatable({}, { __index = _G })
  local chunk = assert(loadfile(dir .. 'effectopacity.lua', 't', env))
  chunk()
  w.env = env
  return w
end

local function lastHello(w)
  local m = w.sent[#w.sent]
  return m and m.buf or nil
end

-- 1. first start, nothing stored, online, engine with marks: both sliders 100, hello need 0, warnings exempt
do
  local w = newWorld()
  w.env.init()
  eq(w.opcode, 164, 'listens on 164')
  eq(type(w.handler), 'function', 'a handler')
  for _, id in ipairs(L.WARNING_IDS) do eq(w.exempt[id], true, 'warning ' .. id .. ' exempt') end
  eq(w.store[L.FLAG], true, 'the first flag is set')
  eq(w.store[L.FLAG_OTHERS], true, 'the second flag is set')
  eq(#w.sent, 1, 'one hello at start')
  eq(lastHello(w), encode({ action = 'hello', need = 0 }), 'hello need 0 at 100 / 100')
  w.env.onOption('opacityOtherEffects', 30)
  eq(lastHello(w), encode({ action = 'hello', need = 1 }), 'others dimmed: need 1')
  eq(#w.sent, 2, 'a second hello')
  w.env.onOption('opacityOtherEffects', 35)
  eq(#w.sent, 2, 'still need 1: nothing new to say')
  w.env.onOption('opacityEffects', 35)
  eq(lastHello(w), encode({ action = 'hello', need = 0 }), 'equal again: need 0')
  w.env.onOption('somethingElse', 5)
  eq(#w.sent, 3, 'another option is ignored')
  eq(w.env.state().own, 35, 'state own')
  eq(w.env.state().others, 35, 'state others')
  w.env.terminate()
  eq(w.unregistered, 164, 'terminate unregisters')
end

-- 2. a saved first value moves to both sliders once (through the settings module)
do
  local w = newWorld({ store = { opacityEffects = 60, ownSpellOpacity = 40 }, settingsModule = true })
  w.env.init()
  eq(w.store.opacityEffects, 40, 'the lowest old value becomes the first slider')
  eq(w.store.opacityOtherEffects, 40, 'and the second one')
  eq(w.applied[1], 'opacityEffects=40', 'the first goes through the settings module')
  eq(w.applied[2], 'opacityOtherEffects=40', 'then the second')
  eq(lastHello(w), encode({ action = 'hello', need = 0 }), 'equal: need 0')
  -- the next start: no second migration
  local w2 = newWorld({ store = { opacityEffects = 40, opacityOtherEffects = 80, [L.FLAG] = true, [L.FLAG_OTHERS] = true }, settingsModule = true })
  w2.env.init()
  eq(#w2.applied, 0, 'migrated: nothing applied')
  eq(w2.store.opacityOtherEffects, 80, 'the second slider is kept')
  eq(lastHello(w2), encode({ action = 'hello', need = 1 }), 'different: need 1')
end

-- 3. without the settings module's option the value goes to g_settings and the alpha
do
  local w = newWorld({ store = { opacityEffects = 55 } })
  w.env.init()
  eq(w.store.opacityOtherEffects, 55, 'the other slider copies it')
  eq(w.alphas.other, 0.55, 'the other alpha follows')
  eq(w.alphas.own, 0.55, 'the first migration applies the own alpha too')
end

-- 4. marks: handed to the engine as source 1; junk ignored
do
  local w = newWorld()
  w.env.init()
  w.handler(nil, 164, { action = 'marks', data = { b = { 32000, 32100, 7 }, m = { 0, 0, 0, 3001, 1, 2, 2, 12 } } })
  eq(#w.marked, 1, 'one call')
  eq(w.marked[1].source, 1, 'source own')
  eq(w.marked[1].x, 32000, 'x')
  eq(w.marked[1].n, 8, 'two groups')
  w.handler(nil, 164, { action = 'marks', data = { b = { 1, 2 }, m = { 0, 0, 0, 5 } } })
  w.handler(nil, 164, 'junk')
  w.handler(nil, 164, nil)
  eq(#w.marked, 1, 'bad messages are dropped')
end

-- 5. an engine without markEffectSources never asks and ignores marks
do
  local w = newWorld({ marks = false, store = { opacityEffects = 100, opacityOtherEffects = 20, [L.FLAG] = true, [L.FLAG_OTHERS] = true } })
  w.env.init()
  eq(lastHello(w), encode({ action = 'hello', need = 0 }), 'no engine part: need 0 although the sliders differ')
  w.handler(nil, 164, { action = 'marks', data = { b = { 1, 2, 7 }, m = { 0, 0, 0, 5 } } })
  eq(#w.marked, 0, 'nothing to hand to')
  eq(w.warned, nil, 'no warning logged')
end

-- 6. not online at load: no hello until the game starts, then one
do
  local w = newWorld({ online = false, store = { opacityEffects = 100, opacityOtherEffects = 50, [L.FLAG] = true, [L.FLAG_OTHERS] = true } })
  w.env.init()
  eq(#w.sent, 0, 'offline: nothing sent')
  w.env.onOption('opacityOtherEffects', 20)
  eq(#w.sent, 0, 'offline slider move: nothing sent')
  w.online = true
  w.game.onGameStart()
  eq(#w.sent, 1, 'game start: hello')
  eq(lastHello(w), encode({ action = 'hello', need = 1 }), 'need 1')
  w.game.onGameStart()
  eq(#w.sent, 2, 'every game start says hello again')
  w.game.onGameEnd()
  w.env.onOption('opacityOtherEffects', 20)
  eq(#w.sent, 3, 'after a game end the next move says it again')
  w.env.terminate()
  eq(lastHello(w), encode({ action = 'hello', need = 0 }), 'terminate asks the server to stop')
end

print(string.format('effectopacity_glue_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
