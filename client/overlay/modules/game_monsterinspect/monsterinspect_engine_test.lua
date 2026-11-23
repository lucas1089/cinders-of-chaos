-- luajit monsterinspect_engine_test.lua && lua5.3 monsterinspect_engine_test.lua (from any folder)
-- The engine part of the Inspect Monster window (monsterinspect.lua, O721) on a fake engine: the menu entry ("Inspect", on a
-- monster only), Shift + left click on a monster (and no other click: the base handler gets those, with its arguments), the
-- request it sends (opcode 166, the creature id), the rows it draws from a result (a part-by-part one too), the refusal text,
-- an answer to an older request ignored, and a clean unload (the hook removed, the click handler put back).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the fake engine
function tr(s, ...) if select('#', ...) > 0 then return string.format(s, ...) end return s end
local created = {}
local function widget(class)
  local w = { class = class, texts = {}, children = {}, shown = true }
  setmetatable(w, { __index = function(t, k)
    if type(k) ~= 'string' then return nil end
    if k == 'destroyChildren' then return function(self) self.children = {} end end
    if k == 'destroy' then return function(self) self.destroyed = true end end
    if k == 'show' then return function(self) self.shown = true end end
    if k == 'hide' then return function(self) self.shown = false end end
    if k:sub(1, 3) == 'set' then return function(self, v) rawset(self, k:sub(4, 4):lower() .. k:sub(5), v) end end
    if k == 'raise' or k == 'focus' or k == 'isVisible' then return function() return true end end
    local child = widget(k)
    rawset(t, k, child)
    return child
  end })
  return w
end
local window
g_ui = {
  displayUI = function(name) window = widget('window') return window end,
  createWidget = function(style, parent)
    local w = widget(style)
    parent.children[#parent.children + 1] = w
    created[#created + 1] = w
    return w
  end,
}
local sent = {}
local protocol = { sendExtendedOpcode = function(self, op, text) sent[#sent + 1] = { op = op, text = text } end }
g_game = { getProtocolGame = function() return protocol end }
local mods = { ctrl = false, shift = false, alt = false }
g_keyboard = { isCtrlPressed = function() return mods.ctrl end, isShiftPressed = function() return mods.shift end,
  isAltPressed = function() return mods.alt end }
MouseLeftButton, MouseRightButton = 1, 2
g_logger = { warning = function(t) print('WARN ' .. t) fails = fails + 1 end }
function connect() end
function disconnect() end
local opcodes = {}
ProtocolGame = { registerExtendedOpcode = function(op, fn) opcodes[op] = fn end, unregisterExtendedOpcode = function(op) opcodes[op] = nil end }
-- a tiny JSON: the tests send tables the module re-encodes, so the fake keeps them by key
local store = {}
local function key(t) store[#store + 1] = t return '#' .. #store end
json = { encode = function(t) return key(t) end, decode = function(s)
  if s:sub(1, 1) == '#' then return store[tonumber(s:sub(2))] end
  error('bad json')
end }

local hooks, removed = {}, {}
local baseCalls = {}
local function base(...) baseCalls[#baseCalls + 1] = { ... } return 'base' end
modules = { game_interface = {
  addMenuHook = function(id, label, fn, filter) hooks[id] = { label = label, fn = fn, filter = filter } end,
  removeMenuHook = function(id) removed[#removed + 1] = id hooks[id] = nil end,
  processMouseAction = base,
} }

local function creature(id, kind, name)
  return { getId = function() return id end, getName = function() return name or 'Slagborer' end,
    isMonster = function() return kind == 'monster' end, isPlayer = function() return kind == 'player' end,
    isNpc = function() return kind == 'npc' end }
end

dofile(dir .. 'monsterinspect_logic.lua')
dofile(dir .. 'monsterinspect.lua')
init()
local gi = modules.game_interface
local hook = hooks.chaosInspectMonster
eq(hook ~= nil, true, 'the menu entry is added')
eq(hook.label, 'Inspect', 'its label is the key "Inspect" (pt-BR Inspecionar)')
eq(hook.filter(nil, nil, nil, creature(5, 'monster')), true, 'offered on a monster')
eq(hook.filter(nil, nil, nil, creature(6, 'player')), false, 'not on a player')
eq(hook.filter(nil, nil, nil, creature(7, 'npc')), false, 'not on an NPC')
eq(hook.filter(nil, nil, nil, nil), false, 'not on an item or the ground')
eq(opcodes[166] ~= nil, true, 'opcode 166 is registered')
eq(gi.processMouseAction ~= base, true, 'the click handler is wrapped')

-- the menu entry sends the request
hook.fn(nil, nil, nil, creature(5, 'monster'))
eq(#sent, 1, 'one request')
eq(sent[1].op, 166, 'on opcode 166')
local msg = store[tonumber(sent[1].text:sub(2))]
eq(msg.action, 'inspect', 'inspect')
eq(msg.data.cid, 5, 'the creature id')
eq(window.statusLabel.text, 'Inspecting...', 'the status says it is asking')
eq(window.headPanel.monsterName.text, 'Slagborer', 'the name shows at once')
-- the menu entry on a player does nothing
hook.fn(nil, nil, nil, creature(6, 'player'))
eq(#sent, 1, 'a player sends nothing')

-- clicks
local TILE, POS = {}, {}
local function click(button, creatureThing, m)
  mods.ctrl, mods.shift, mods.alt = m and m.ctrl or false, m and m.shift or false, m and m.alt or false
  return gi.processMouseAction(TILE, POS, button, { x = 1 }, 'look', 'use', creatureThing, 'attack')
end
local before = #sent
eq(click(MouseLeftButton, creature(5, 'monster'), { shift = true }), true, 'shift + left is taken')
eq(#sent, before + 1, 'and sends the request')
eq(#baseCalls, 0, 'the base handler did not run for it')
eq(click(MouseRightButton, creature(5, 'monster'), { shift = true }), 'base', 'shift + right goes to the base (Look)')
eq(click(MouseLeftButton, creature(5, 'monster'), {}), 'base', 'a plain left click goes to the base (attack)')
eq(click(MouseLeftButton, creature(5, 'monster'), { ctrl = true, shift = true }), 'base', 'ctrl + shift goes to the base')
eq(click(MouseLeftButton, creature(6, 'player'), { shift = true }), 'base', 'shift + left on a player goes to the base (Look)')
eq(click(MouseLeftButton, nil, { shift = true }), 'base', 'shift + left on an item goes to the base (Look)')
eq(#sent, before + 1, 'none of those sent a request')
eq(#baseCalls, 5, 'the base handler ran five times')
local last = baseCalls[#baseCalls]
eq(last[1], TILE, 'the base gets the tile first')
eq(last[3], MouseLeftButton, 'its mouse button')
eq(last[5], 'look', 'its look thing')
eq(last[7], nil, 'its creature (nil here)')
eq(baseCalls[1][7] ~= nil, true, 'a creature reaches the base untouched')
eq(baseCalls[1][8], 'attack', 'every later argument reaches the base')

-- a result
local function answer(action, data)
  local text = json.encode({ action = action, data = data })
  opcodes[166](protocol, 166, text)
end
local result = { cid = 5, name = 'Slagborer', level = 412, flags = { { key = 'boss' } }, health = { cur = 450, max = 900, pct = 50 },
  outfit = { lookType = 110 }, exp = { base = 450, total = 450 }, attacks = { { name = 'melee', kind = 'melee', min = 0, max = 90 } },
  resist = { elements = { { name = 'fire', pct = -25 } }, immune = {}, conditions = {} } }
eq(click(MouseLeftButton, creature(5, 'monster'), { shift = true }), true, 'inspect again')
answer('result', result)
eq(window.headPanel.monsterName.text, 'Slagborer', 'header name')
eq(window.headPanel.levelLine.text, 'Level 412', 'header level')
eq(window.headPanel.flagsLine.text, 'Boss', 'header flags')
eq(window.headPanel.healthBar.percent, 50, 'health bar')
eq(window.headPanel.healthBar.text, 'Health: 450 / 900 (50%)', 'health bar text')
eq(window.headPanel.creature.outfit.type, 110, 'the creature is drawn')
local list = window.listPanel.list
eq(#list.children > 4, true, 'rows were drawn (' .. #list.children .. ')')
local names = {}
local function textOf(w, id)
  local c = rawget(w, id)
  local t = c and rawget(c, 'text')
  return type(t) == 'string' and t or nil
end
for _, w in ipairs(list.children) do names[#names + 1] = textOf(w, 'title') or textOf(w, 'name') or rawget(w, 'text') or '?' end
local joined = table.concat(names, '|')
eq(joined:find('Experience', 1, true) ~= nil, true, 'the experience section is there')
eq(joined:find('Resistances', 1, true) ~= nil and joined:find('Fire', 1, true) ~= nil, true, 'the resistances are there')
eq(joined:find('Melee', 1, true) ~= nil, true, 'the attacks are there')
eq(window.statusLabel.text, '', 'the status is cleared')

-- an answer for another creature is ignored
local rows = #list.children
answer('result', { cid = 99, name = 'Other', health = { pct = 10 } })
eq(window.headPanel.monsterName.text, 'Slagborer', 'a late answer for another monster is ignored')
eq(#list.children, rows, 'and draws nothing')

-- a result in parts
local whole = { action = 'result', data = result }
local wholeKey = json.encode(whole)
opcodes[166](protocol, 166, 'S' .. wholeKey:sub(1, 1))
opcodes[166](protocol, 166, 'E' .. wholeKey:sub(2))
eq(#list.children, rows, 'a result in parts draws the same rows')

-- a refusal
answer('denied', { code = 'range' })
eq(window.statusLabel.text, 'That monster is too far away or out of sight.', 'the refusal text')
eq(#list.children, 0, 'the list is cleared')
-- a broken packet does not stop anything
opcodes[166](protocol, 166, 'not json')
opcodes[166](protocol, 166, '')
answer('result', { cid = 5 })
eq(fails, 0, 'no warning logged')

-- refresh asks again for the same monster
before = #sent
refresh()
eq(#sent, before + 1, 'refresh sends a request')
eq(store[tonumber(sent[#sent].text:sub(2))].data.cid, 5, 'for the same creature')

-- an unload puts everything back
terminate()
eq(gi.processMouseAction, base, 'the click handler is put back')
eq(removed[1], 'chaosInspectMonster', 'the menu entry is removed')
eq(opcodes[166], nil, 'the opcode is released')
eq(window.destroyed, true, 'the window is destroyed')

-- another module wrapped the click handler after us: it is left alone on unload
init()
local mine = gi.processMouseAction
local theirs = function(...) return mine(...) end
gi.processMouseAction = theirs
terminate()
eq(gi.processMouseAction, theirs, 'a handler wrapped by another module after ours is not undone')

if fails > 0 then
  print(fails .. ' of ' .. checks .. ' checks failed')
  os.exit(1)
end
print('monsterinspect_engine_test: all ' .. checks .. ' checks passed')
