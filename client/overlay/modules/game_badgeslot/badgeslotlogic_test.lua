-- luajit badgeslotlogic_test.lua && lua5.3 badgeslotlogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'badgeslotlogic.lua')
local L = BadgeSlotLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.SLOT, 13, 'the badge slot is inventory slot 13')
eq(L.slotTooltip(13, false), 'Badge', 'empty: "Badge"')
eq(L.slotTooltip(13, true), '', 'an item in it: its own tooltip')
eq(L.slotTooltip('13', false), 'Badge', 'a slot number as text')
eq(L.slotTooltip(10, false), nil, 'the ammunition slot is not drawn and left as it is')
eq(L.slotTooltip(9, false), nil, 'the ring slot is left as it is')
eq(L.SOUL_TOOLTIP:lower():find('ammunition', 1, true), nil, 'the soul tooltip names no ammunition')
eq(L.SOUL_TOOLTIP:find('runes', 1, true) ~= nil, true, 'it still names runes')

-- base patch 0113 draws slot 13 where slot 10 was, with the badge image
local function read(p) local f = io.open(p, 'r') if not f then return nil end local s = f:read('*a') f:close() return s end
local patch = read(dir .. '../../../base-patches/0113-badge-slot.patch')
eq(patch ~= nil, true, 'base patch 0113 is there')
if patch then
  eq(patch:find('+  id: slot13', 1, true) ~= nil, true, '0113: the inventory widget slot13')
  eq(patch:find('+  &position: {x=65535, y=13, z=0}', 1, true) ~= nil, true, '0113: its position is inventory slot 13')
  eq(patch:find('+  image-source: /images/game/slots/badge', 1, true) ~= nil, true, '0113: the badge image')
  eq(patch:find('+InventorySlotBadge = 13', 1, true) ~= nil, true, '0113: InventorySlotBadge')
end
local img = io.open(dir .. '../../data/images/game/slots/badge.png', 'rb')
eq(img ~= nil, true, 'the badge placeholder image is there (client/tools/gen_skin.py)')
if img then img:close() end

if fails > 0 then print('badgeslotlogic_test: ' .. fails .. ' failure(s)') os.exit(1) end
print('badgeslotlogic_test: ' .. checks .. ' checks ok')
