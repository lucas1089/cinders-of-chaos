-- luajit lockmenu_test.lua && lua5.3 lockmenu_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'lockmenu.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local L = CraftingLockMenu
local function info(o)
  o.pos = o.pos or { x = 65535, y = 0x40, z = 3 }
  return o
end

-- positions
eq(L.ownPosition({ x = 65535, y = 4, z = 0 }).y, 4, 'inventory slot')
eq(L.ownPosition({ x = 65535, y = 13, z = 0 }).y, 13, 'badge slot')
eq(L.ownPosition({ x = 65535, y = 10, z = 0 }), nil, 'slot 10 takes nothing')
eq(L.ownPosition({ x = 65535, y = 11, z = 0 }), nil, 'the store inbox slot')
eq(L.ownPosition({ x = 65535, y = 0x41, z = 7 }).z, 7, 'container slot')
eq(L.ownPosition({ x = 65535, y = 0x50, z = 0 }), nil, 'past the container ids')
eq(L.ownPosition({ x = 65535, y = 0x40, z = -1 }), nil, 'negative slot')
eq(L.ownPosition({ x = 32000, y = 32000, z = 7 }), nil, 'a map tile')
eq(L.ownPosition(nil), nil, 'nothing')

-- which items get an entry
eq(L.applies(info({ rarity = 3 })), true, 'rolled gear')
eq(L.applies(info({ unique = true })), true, 'unique')
eq(L.applies(info({ name = 'Rift Key' })), true, 'a Rift Key by name')
eq(L.applies(info({})), false, 'a plain item')
eq(L.applies(info({ rarity = 3, stackable = true })), false, 'stackable')
eq(L.applies(info({ rarity = 3, container = true })), false, 'container')
eq(L.applies(info({ rarity = 3, pos = { x = 32000, y = 32000, z = 7 } })), false, 'ground items never')
eq(L.applies(info({ locked = true })), true, 'a locked item can always be unlocked')
eq(L.applies(nil), false, 'no info')

-- Lock item / Unlock item
eq(L.show(info({ rarity = 3 }), false), true, 'unlocked: Lock item')
eq(L.show(info({ rarity = 3 }), true), false, 'unlocked: no Unlock item')
eq(L.show(info({ rarity = 3, locked = true }), true), true, 'locked: Unlock item')
eq(L.show(info({ rarity = 3, locked = true }), false), false, 'locked: no Lock item')
eq(L.show(info({}), false), false, 'plain item: no entry')

-- the request
local r = L.request(info({ rarity = 3 }), 2450, true)
eq(r.cid, 2450, 'request cid')
eq(r.on, true, 'request on')
eq(r.pos.y, 0x40, 'request pos')
eq(r.pos.z, 3, 'request slot')
eq(L.request(info({ pos = { x = 1, y = 2, z = 3 } }), 2450, true), nil, 'no request for the map')
eq(L.request(info({}), nil, true), nil, 'no request without an id')

if fails > 0 then os.exit(1) end
print('lockmenu_test: ok (' .. checks .. ' checks)')
