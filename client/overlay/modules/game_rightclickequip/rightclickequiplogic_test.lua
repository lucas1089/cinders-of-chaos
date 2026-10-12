-- luajit rightclickequiplogic_test.lua && lua5.3 rightclickequiplogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'rightclickequiplogic.lua')
local L = RightClickEquipLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the protocol, the same numbers as the server (chaos_constants.lua ChaosOpcodes.rightClickEquip)
eq(L.OPCODE, 188, 'opcode')
eq(L.OPTION, 'rightClickEquip', 'option id (dataset.lua and interface.otui, base patch 0037)')
local f = io.open(dir .. '../../../../server/data/scripts/chaos/chaos_constants.lua', 'r')
if f then
  local text = f:read('*a'); f:close()
  eq(text:find('ChaosOpcodes.rightClickEquip = 188', 1, true) ~= nil, true, 'server constant matches')
end

-- the option: on unless explicitly off (an older settings module without it: on, the server's default)
eq(L.isOn(nil), true, 'no option: on')
eq(L.isOn(true), true, 'true: on')
eq(L.isOn(false), false, 'false: off')
eq(L.isOn(0), false, '0: off')
eq(L.isOn('false'), false, 'text false: off')
eq(L.isOn(1), true, '1: on')

-- the message
eq(L.message(true).on, true, 'message on')
eq(L.message(false).on, false, 'message off')
eq(L.message(nil).on, false, 'message of nil is a boolean')
local keys = 0
for _ in pairs(L.message(true)) do keys = keys + 1 end
eq(keys, 1, 'one field')

-- when to send: a new session always, then only a change
eq(L.needsSend(nil, true, false), true, 'first send of a session')
eq(L.needsSend(true, true, false), false, 'same value: nothing')
eq(L.needsSend(true, false, false), true, 'turned off')
eq(L.needsSend(false, true, false), true, 'turned on')
eq(L.needsSend(false, false, true), true, 'forced (game start)')
eq(L.needsSend(true, 1, false), false, 'a truthy value counts as on')

-- the server's list of multi-use weapons
local set = L.idSet({3264, '3265', 'x'})
eq(set[3264], true, 'id in the set'); eq(set[3265], true, 'text id'); eq(set[3308], nil, 'a tool is not')
eq(next(L.idSet(nil)), nil, 'no list: empty set')

-- the mouse: which click is the preset's use (the base starts a use with there for a multi-use item)
local none, ctrl, shift, alt = {}, { ctrl = true }, { shift = true }, { alt = true }
eq(L.useClick(1, 'right', none), true, 'classic: right-click')
eq(L.useClick(1, 'left', none), false, 'classic: left-click walks')
eq(L.useClick(1, 'right', ctrl), false, 'classic: ctrl + right is the menu')
eq(L.useClick(1, 'right', shift), false, 'classic: shift + right is left to the base')
eq(L.useClick(1, 'right', alt), false, 'classic: alt + right is left to the base')
eq(L.useClick(1, 'right', none, true), false, 'classic: both buttons look')
eq(L.useClick(2, 'right', none), false, 'regular: right-click is the menu')
eq(L.useClick(2, 'left', ctrl), true, 'regular: ctrl + left uses')
eq(L.useClick(2, 'right', ctrl), true, 'regular: ctrl + right uses')
eq(L.useClick(2, 'left', { ctrl = true, shift = true }), false, 'regular: ctrl + shift is not the use')
eq(L.useClick(2, 'left', shift), false, 'regular: shift + left looks')
eq(L.useClick(3, 'left', none), true, 'smart: left-click uses')
eq(L.useClick(3, 'right', none), false, 'smart: right-click is the menu')
eq(L.useClick(3, 'left', alt), false, 'smart: alt + left quick loots')
eq(L.useClick(nil, 'right', none), true, 'no preset: classic')
eq(L.useClick(9, 'right', none), true, 'unknown preset: classic')

-- where: an inventory slot or an open container (the map keeps the base behaviour)
eq(L.inContainerOrInventory({ x = 0xFFFF, y = 6, z = 0 }), true, 'weapon hand')
eq(L.inContainerOrInventory({ x = 0xFFFF, y = 0x40 + 2, z = 7 }), true, 'container 2, slot 7')
eq(L.inContainerOrInventory({ x = 0xFFFF, y = 0, z = 0 }), false, 'the hotkey position')
eq(L.inContainerOrInventory({ x = 0xFFFF, y = 11, z = 0 }), false, 'no slot 11 in this protocol')
eq(L.inContainerOrInventory({ x = 1000, y = 1000, z = 7 }), false, 'on the map')
eq(L.inContainerOrInventory(nil), false, 'no position')

-- the decision
local base = { option = true, multiUse = true, clientId = 3264, ids = set, pos = { x = 0xFFFF, y = 0x40, z = 1 },
  mode = 1, button = 'right', mods = none }
local function with(k, v) local o = {} for a, b in pairs(base) do o[a] = b end o[k] = v return o end
eq(L.shouldEquip(base), true, 'a listed multi-use weapon, right-clicked in the backpack: plain use')
eq(L.shouldEquip(with('option', false)), false, 'option off: the base use with')
eq(L.shouldEquip(with('option', nil)), true, 'no option (older settings): on')
eq(L.shouldEquip(with('multiUse', false)), false, 'not multi-use: the base already sends a use')
eq(L.shouldEquip(with('clientId', 3308)), false, 'a tool (machete): its use with')
eq(L.shouldEquip(with('pos', { x = 100, y = 100, z = 7 })), false, 'on the map: the base')
eq(L.shouldEquip(with('pos', { x = 0xFFFF, y = 6, z = 0 })), true, 'worn: plain use (takes it off)')
eq(L.shouldEquip(with('mods', ctrl)), false, 'ctrl + right in classic: the menu')
eq(L.shouldEquip(with('mode', 2)), false, 'regular: right-click is the menu')
local reg = with('mode', 2); reg.mods = ctrl
eq(L.shouldEquip(reg), true, 'regular: ctrl + click')
local smart = with('mode', 3); smart.button = 'left'
eq(L.shouldEquip(smart), true, 'smart: left-click')
eq(L.shouldEquip(with('both', true)), false, 'both buttons: look')
eq(L.shouldEquip(nil), false, 'nothing')

-- the base patch carries the option on by default, under Options > Interface
local p = io.open(dir .. '../../../base-patches/0037-right-click-equip-option.patch', 'r')
eq(p ~= nil, true, 'base patch 0037 present')
if p then
  local text = p:read('*a'); p:close()
  eq(text:find('+\trightClickEquip = {\n+\t\tvalue = true,', 1, true) ~= nil, true, 'dataset: on by default')
  eq(text:find('modules.game_rightclickequip', 1, true) ~= nil, true, 'dataset: tells this module')
  eq(text:find('+      id: rightClickEquip', 1, true) ~= nil, true, 'interface.otui: the checkbox')
  eq(text:find("tr('Right-click equips items')", 1, true) ~= nil, true, 'interface.otui: the label')
end

print(string.format('rightclickequiplogic_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
