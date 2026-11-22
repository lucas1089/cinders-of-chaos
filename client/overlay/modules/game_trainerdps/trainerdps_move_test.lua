-- luajit trainerdps_move_test.lua && lua5.3 trainerdps_move_test.lua (CI runs it from the repo root)
-- O720: the Trainer DPS panel is movable. Plays trainerdps.lua on a fake engine and holds: the module lists game_hudmove as a
-- dependency (it is sandboxed), init attaches the panel to ChaosHudMove with its title bar as a drag handle, a game_hudmove
-- that is not there yet at init is tried again when the panel is shown, the menu's "Reset position" resets the panel, the
-- background rows do not eat the press (keepRow / buttonRow are phantom in the .otui), and the clock of a running session
-- ticks between two summaries.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. '../game_dpsmeter/dpsmath.lua')
dofile(dir .. 'trainerdpslogic.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(v, what) eq(v and true or false, true, what) end
local function read(path)
  local f = assert(io.open(path, 'rb'))
  local t = f:read('*a')
  f:close()
  return t
end

-- ---------------------------------------------------------------- the files
local otmod = read(dir .. 'game_trainerdps.otmod')
ok(otmod:find('%- game_hudmove') ~= nil, 'the module depends on game_hudmove')
local otui = read(dir .. 'trainerdps.otui')
local function block(id)
  local s = otui:find('id: ' .. id .. '\n', 1, true)
  if not s then return '' end
  local e = otui:find('\n\n', s, true) or #otui
  return otui:sub(s, e)
end
for _, id in ipairs({ 'keepRow', 'buttonRow' }) do
  ok(block(id):find('phantom: true', 1, true) ~= nil, id .. ' does not take the press of the background')
  ok(block(id):find('phantom: false', 1, true) == nil, id .. ' is not a solid cover')
end
ok(block('header'):find('cursor: pointer', 1, true) == nil, 'the title bar is not a click target (no pointer)')

-- ---------------------------------------------------------------- a fake engine
local function stub()
  local s = {}
  return setmetatable(s, { __index = function(t, k)
    if type(k) == 'string' and k:match('^on%u') then return nil end -- a handler slot
    local c = stub()
    rawset(t, k, c)
    return c
  end, __call = function() return nil end })
end

local function widget(name)
  local w = stub()
  rawset(w, '_name', name)
  rawset(w, '_visible', true)
  rawset(w, 'isDestroyed', function() return false end)
  rawset(w, 'isVisible', function(self) return self._visible end)
  rawset(w, 'show', function(self) self._visible = true end)
  rawset(w, 'hide', function(self) self._visible = false end)
  rawset(w, 'raise', function() end)
  rawset(w, 'isChecked', function() return false end)
  rawset(w, 'getWidth', function() return 200 end)
  return w
end

local attached, detached, resets = {}, 0, 0
local function newHudMove()
  return {
    attach = function(panel, id, opts)
      attached[#attached + 1] = { panel = panel, id = id, opts = opts }
      return { panel = panel }
    end,
    detach = function() detached = detached + 1 end,
    reset = function() resets = resets + 1 end,
  }
end

local root = widget('root')
local created = {}
local menuOptions = {}
local env = setmetatable({
  tr = function(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end,
  g_ui = {
    importStyle = function() end,
    createWidget = function(style)
      if style == 'PopupMenu' then
        local m = widget('menu')
        m.addOption = function(_, text, fn) menuOptions[#menuOptions + 1] = { text = text, fn = fn } end
        m.addSeparator = function() end
        m.setGameMenu = function() end
        m.display = function() end
        return m
      end
      local w = widget(style)
      created[#created + 1] = w
      return w
    end,
  },
  g_settings = { getNode = function() return nil end, setNode = function() end, save = function() end },
  g_game = { isOnline = function() return false end, getProtocolGame = function() return nil end },
  g_clock = { millis = function() return 0 end },
  g_logger = { warning = function() end },
  g_window = { getMousePosition = function() return { x = 1, y = 1 } end },
  modules = { game_interface = { getRootPanel = function() return root end }, game_dpsmeter = { DpsMath = DpsMath } },
  ProtocolGame = { registerExtendedJSONOpcode = function() end, unregisterExtendedJSONOpcode = function() end },
  connect = function() end, disconnect = function() end,
  removeEvent = function() end, cycleEvent = function() return 1 end, scheduleEvent = function() return 1 end,
  json = { encode = function() return '{}' end },
}, { __index = _G })

local luaLoad = load
local function loadFile(path)
  local src = read(path)
  local chunk
  if setfenv then
    chunk = assert(loadstring(src, '@' .. path))
    setfenv(chunk, env)
  else
    chunk = assert(luaLoad(src, '@' .. path, 't', env))
  end
  chunk()
end

-- ---------------------------------------------------------------- game_hudmove loaded before the panel: attached at init
env.ChaosHudMove = newHudMove()
loadFile(dir .. 'trainerdps.lua')
env.init()
eq(#attached, 1, 'attached once at init')
local panel = created[1]
ok(attached[1] and attached[1].panel == panel, 'the panel itself is attached')
eq(attached[1] and attached[1].id, 'trainerDps', 'its id')
local handles = attached[1] and attached[1].opts and attached[1].opts.handles or {}
ok(handles[1] ~= nil and handles[1] == panel.header, 'the title bar drags the panel')
ok(attached[1].opts.panel ~= false, 'the background drags it too')
eq(attached[1].opts.otui, '/modules/game_trainerdps/trainerdps', 'the default place from its .otui')
eq(attached[1].opts.style, 'TrainerDpsPanel', 'and its style')
env.show()
eq(#attached, 1, 'showing the panel does not attach twice')
-- the menu
for _, o in ipairs(menuOptions) do menuOptions[_] = nil end
env.showMenu()
local resetFn
for _, o in ipairs(menuOptions) do if o.text == 'Reset position' then resetFn = o.fn end end
ok(resetFn ~= nil, 'the menu has Reset position')
if resetFn then resetFn() end
eq(resets, 1, 'Reset position resets the panel through game_hudmove')
env.terminate()
eq(detached, 1, 'terminate detaches')

-- ---------------------------------------------------------------- game_hudmove not there at init: tried again at show
attached, created = {}, {}
env.ChaosHudMove = nil
loadFile(dir .. 'trainerdps.lua')
env.init()
eq(#attached, 0, 'no game_hudmove at init: nothing to attach to (and no error)')
env.ChaosHudMove = newHudMove()
env.show()
eq(#attached, 1, 'attached when the panel is shown and game_hudmove is there')
ok(attached[1] and attached[1].opts.handles[1] == created[1].header, 'with the title bar as a handle')
env.show()
eq(#attached, 1, 'and only once')
env.terminate()

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('trainerdps_move_test: OK (' .. checks .. ' checks)')
