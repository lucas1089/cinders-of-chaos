-- luajit containers_test.lua && lua5.3 containers_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. '../client_chaos_settings/settingslist.lua') -- ChaosSettings: the g_settings round trip
dofile(dir .. 'layout_logic.lua')
dofile(dir .. 'containers_logic.lua')
local C = ChaosContainerLogic
local L = ChaosLayoutLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- keys
eq(C.keyOf({ { i = 3, id = 2854 }, { i = 1, id = 1987 } }), '3_2854/1_1987', 'a key')
eq(C.keyOf({ { i = 0, id = 2854 } }), nil, 'slot 0 is no inventory slot')
eq(C.keyOf({ { i = 12, id = 2854 } }), nil, 'nor 12')
eq(C.keyOf({ { i = 11, id = 26052 } }), '11_26052', 'the purse')
eq(C.keyOf({ { i = 3, id = 2854 }, { i = -1, id = 1987 } }), nil, 'a negative index')
eq(C.keyOf({}), nil, 'no steps')
local deep = {}
for k = 1, C.MAX_DEPTH + 1 do deep[k] = { i = 3, id = 1 } end
eq(C.keyOf(deep), nil, 'too deep')
local s = C.parse('3_2854/1_1987/0_1991')
eq(#s, 3, 'parsed') eq(s[2].i, 1, 'index') eq(s[3].id, 1991, 'id')
eq(C.parse('3_2854//1_1987'), nil, 'an empty step')
eq(C.parse('3-2854'), nil, 'not a key')
eq(C.parse('03_2854'), nil, 'not the canonical text')
eq(C.parse(nil), nil, 'nothing')
eq(C.parentKey('3_2854/1_1987/0_1991'), '3_2854/1_1987', 'the parent')
eq(C.parentKey('3_2854'), nil, 'the slot container has none')
eq(C.depth('3_2854/1_1987'), 2, 'depth')

-- the key of an item the player opens, from its position
local known = { [0] = '3_2854', [4] = '3_2854/1_1987' }
eq(C.fromPosition({ x = 65535, y = 3, z = 0 }, 2854, known), '3_2854', 'the backpack slot')
eq(C.fromPosition({ x = 65535, y = 64, z = 5 }, 1987, known), '3_2854/5_1987', 'the 6th item of container 0')
eq(C.fromPosition({ x = 65535, y = 68, z = 0 }, 1991, known), '3_2854/1_1987/0_1991', 'a bag in a bag')
eq(C.fromPosition({ x = 65535, y = 70, z = 0 }, 1991, known), nil, 'a container this module did not see open')
eq(C.fromPosition({ x = 100, y = 100, z = 7 }, 1987, known), nil, 'a bag on the map')
eq(C.fromPosition(nil, 1987, known), nil, 'no position')

-- snapshot: panel order, valid keys only, at most C.MAX
local snap = C.snapshot({
  { key = '3_2854/1_1987', panel = 'gameRightPanel', side = 'right', panelOrder = 1, index = 5, height = 120 },
  { key = '3_2854', panel = 'gameRightPanel', side = 'right', panelOrder = 1, index = 3, height = 200, scroll = 34 },
  { key = nil, panel = 'gameRightPanel', side = 'right', index = 4 },
  { key = '10_2591', panel = 'gameLeftPanel', side = 'left', panelOrder = 1, index = 1, height = 90, minimized = true },
})
eq(#snap, 3, 'three named containers')
eq(snap[1].key, '10_2591', 'the left panel first')
eq(snap[2].key, '3_2854', 'then the right one by index')
eq(snap[2].scroll, 34, 'its scroll') eq(snap[3].scroll, nil, 'no scroll kept at 0')
eq(snap[1].minimized, true, 'minimized')
local many = {}
for k = 1, C.MAX + 4 do many[k] = { key = '3_2854/' .. k .. '_1987', panel = 'p', side = 'right', index = k } end
eq(#C.snapshot(many), C.MAX, 'capped')

-- the saved list survives the g_settings round trip (list index 1 comes back as the tag "1")
local settings = ChaosSettings.mockSettings()
settings.setNode('chaos_layout', { ['W/Alice'] = { containers = snap } })
local back = settings.getNode('chaos_layout')['W/Alice'].containers
local entries = C.entries(back)
eq(#entries, 3, 'read back') eq(entries[2].key, '3_2854', 'in order') eq(entries[1].minimized, true, 'booleans typed')
eq(entries[2].height, 200, 'numbers typed')

-- the plan: parents first, open ones skipped, a parent neither open nor saved opened for a while
local saved = {
  { key = '3_2854/1_1987/0_1991', panel = 'p', index = 4 },
  { key = '3_2854', panel = 'p', index = 2 },
  { key = '10_2591', panel = 'p', index = 3 },
}
local plan = C.plan(saved, {})
eq(#plan, 4, 'three saved and one parent')
eq(plan[1].key, '3_2854', 'the backpack first') eq(plan[1].transient, nil, 'saved: stays open')
eq(plan[2].key, '10_2591', 'the quiver (depth 1, saved later)')
eq(plan[3].key, '3_2854/1_1987', 'the bag on the way') eq(plan[3].transient, true, 'not saved: closed again')
eq(plan[4].key, '3_2854/1_1987/0_1991', 'the green bag last')
plan = C.plan(saved, { ['3_2854'] = true, ['3_2854/1_1987/0_1991'] = true })
eq(#plan, 1, 'what is open already is left') eq(plan[1].key, '10_2591', 'the quiver only')
eq(#C.plan(nil, {}), 0, 'nothing saved')
eq(#C.plan({ { key = 'junk' } }, {}), 0, 'a bad key is skipped')

-- which item of the parent opens
local items = { { index = 0, id = 2148, container = false }, { index = 1, id = 1987 }, { index = 2, id = 1987 } }
eq(C.resolve(items, { i = 1, id = 1987 }), 1, 'the same index')
eq(C.resolve(items, { i = 0, id = 1987 }), 1, 'moved: the first bag')
eq(C.resolve(items, { i = 1, id = 1987 }, { [1] = true }), 2, 'the first bag is taken: the next one')
eq(C.resolve(items, { i = 0, id = 2148 }), nil, 'not a container')
eq(C.resolve(items, { i = 5, id = 9999 }), nil, 'gone: skipped')

-- placement
local place = C.placement({
  { key = '3_2854', panel = 'gone', side = 'right', index = 4 },
  { key = '10_2591', panel = 'gameRightPanel', side = 'right', index = 2 },
  { key = '3_2854/1_1987', panel = 'gone', side = 'top', index = 1 },
}, { gameRightPanel = 'right' }, { right = 'gameRightPanel', left = 'gameLeftPanel' })
eq(#place, 2, 'a panel of no side is dropped')
eq(place[1].key, '10_2591', 'by index') eq(place[2].panel, 'gameRightPanel', 'a gone panel: the first of its side')

-- the option and the pending opens
eq(C.enabled(nil), true, 'on by default') eq(C.enabled(true), true, 'on') eq(C.enabled(false), false, 'off')
local pending = { { key = 'a', id = 1, at = 0 }, { key = 'b', id = 2, at = 1000 }, { key = 'c', id = 2, at = 2000 } }
local key, rest = C.takePending(pending, 2, 2500)
eq(key, 'b', 'the oldest of that id') eq(#rest, 2, 'the others stay')
key, rest = C.takePending(rest, 2, 2000 + C.PENDING_MS + 1)
eq(key, nil, 'too late') eq(#rest, 0, 'and dropped')
key = C.takePending({ { key = 'up', at = 0 } }, 77, 10)
eq(key, 'up', 'an open of any id (the up arrow)')
key, rest = C.takePending({ { key = 'x', id = 5, cid = 2, at = 0 }, { key = 'y', id = 5, cid = 3, at = 0 } }, 5, 10, 3)
eq(key, 'y', 'the container id g_game.open asked for') eq(rest[1].key, 'x', 'the other one waits')

-- the layout keeps its containers through a merge and a change shows
local merged = L.merge({ mini = {}, containers = saved }, { mini = {}, panels = {} })
eq(merged.containers, saved, 'a snapshot without containers keeps the saved ones')
merged = L.merge({ mini = {}, containers = saved }, { mini = {}, panels = {}, containers = {} })
eq(#merged.containers, 0, 'a snapshot with none open saves none')

if fails > 0 then print('containers_test: ' .. fails .. ' failure(s)') os.exit(1) end
print('containers_test: ok')
