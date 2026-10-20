-- luajit lootbeams_test.lua && lua5.3 lootbeams_test.lua (from any folder)
-- Loot beam rules with the real loot filter rules (game_lootfilter/lootfilterlogic.lua): settings, tier -> colour
-- (the rarity ids in four colours, uniques and orbs apart), the filter, the best item per tile, the server's beam messages
-- (start, change, looted empty), ground items, the cap with many corpses, and the engine calls of a change.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. '../game_lootfilter/lootfilterlogic.lua')
dofile(dir .. 'lootbeamslogic.lua')
local L, LB = LootFilterLogic, LootBeamsLogic
LB.setFilterLogic(L)
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- ---------------------------------------------------------------- settings
local d = LB.defaults()
eq(d.enabled, true, 'on by default')
eq(d.height, 'normal', 'normal height')
eq(d.intensity, 'normal', 'normal intensity')
eq(d.orbs, false, 'no orb beams by default')
eq(d.ground, true, 'ground items by default')
local s = LB.normalize({ enabled = 'false', height = 'huge', intensity = 'bright', orbs = 'true' })
eq(s.enabled, false, 'g_settings strings: false')
eq(s.height, 'normal', 'unknown height')
eq(s.intensity, 'bright', 'bright')
eq(s.orbs, true, 'g_settings strings: true')
eq(LB.normalize(nil).ground, true, 'nil = defaults')
eq(LB.HEIGHTS.short < LB.HEIGHTS.normal and LB.HEIGHTS.normal < LB.HEIGHTS.tall, true, 'heights grow')
eq(LB.HEIGHTS.normal >= 3 and LB.HEIGHTS.normal <= 4, true, 'normal is 3-4 tiles')

-- ---------------------------------------------------------------- tiers and colours
eq(#LB.TIER_GROUP, 15, 'every tier has a group')
eq(#LB.TIER_GROUP, #L.RARITY, 'as many ids as the loot filter')
local groups = {}
for r = 1, 15 do
  local g = LB.TIER_GROUP[r]
  eq(LB.GROUPS[g] ~= nil, true, 'tier ' .. r .. ' group exists')
  groups[g] = true
  eq(LB.tierColor(r), LB.GROUPS[g].color, 'tier ' .. r .. ' colour')
end
eq(count(groups), 4, 'four beam colours for the rarities')
eq(groups.unique, nil, 'uniques are not a tier colour')
eq(LB.TIER_GROUP[5], 'orange', 'Legendary is orange')
eq(LB.TIER_GROUP[7], 'orange', 'an old Mythic is Legendary: orange')
eq(LB.TIER_GROUP[10], 'divine', 'Divine')
eq(LB.TIER_GROUP[1], 'white', 'Common is white')
eq(LB.TIER_GROUP[3], 'blue', 'Magic is blue') eq(LB.TIER_GROUP[4], 'blue', 'Rare is blue')
eq(LB.TIER_GROUP[15], 'divine', 'an old Transcendent is Divine')
eq(LB.groupOf({ u = 1, r = 5 }), 'unique', 'a unique has its own colour, whatever its rarity')
eq(LB.groupOf({ o = 1 }), 'orb', 'orbs')
eq(LB.groupOf({ pw = 1 }), 'orange', 'a power on plain gear: legendary colour')
eq(LB.groupOf({ g = 'currency' }), nil, 'coins: no beam colour')
eq(LB.groupOf(nil), nil, 'nothing')
eq(LB.tierColor(0), nil, 'no rarity')
eq(LB.tierColor(16), nil, 'beyond the table')
local colours = {}
for _, key in ipairs(LB.GROUP_ORDER) do
  local c = LB.GROUPS[key].color
  eq(c:match('^#%x%x%x%x%x%x$') ~= nil, true, key .. ' colour is #rrggbb')
  eq(colours[c], nil, key .. ' colour is its own')
  colours[c] = true
end
eq(LB.GROUPS.white.height < LB.GROUPS.divine.height, true, 'higher tiers stand taller')
eq(LB.rank({ u = 1 }) > LB.rank({ r = 15 }), true, 'a unique beats every tier')
eq(LB.rank({ r = 10 }) > LB.rank({ r = 5 }), true, 'higher rarity wins')
eq(LB.rank({ r = 1 }) > LB.rank({ o = 1 }), true, 'orbs rank last')

-- ---------------------------------------------------------------- the loot filter decides
local filter = L.defaults() -- glow on gear from Rare (3)
local gear = function(r) return { r = r, g = 'equipment' } end
eq(LB.wants(gear(3), filter, d), true, 'Rare glows under the default filter: beam')
eq(LB.wants(gear(2), filter, d), false, 'Uncommon does not glow: no beam')
eq(LB.wants({ u = 1, g = 'equipment' }, filter, d), true, 'uniques always glow')
eq(LB.wants({ pw = 1, r = 1, g = 'equipment' }, filter, d), true, 'a legendary power always glows')
eq(LB.wants({ o = 1, g = 'currency' }, filter, d), false, 'orbs: off by default')
eq(LB.wants({ o = 1, g = 'currency' }, filter, LB.normalize({ orbs = true })), true, 'orbs when wanted')
eq(LB.wants({ g = 'currency' }, filter, d), false, 'coins never')
local strict = L.normalize({ highlight = 10 })
eq(LB.wants(gear(5), strict, d), false, 'a stricter filter: Legendary no longer beams')
eq(LB.wants(gear(10), strict, d), true, 'Divine still does')
local off = L.normalize({ highlight = 0 })
eq(LB.wants(gear(10), off, d), false, 'rarity glow off: no rarity beams')
eq(LB.wants({ u = 1 }, off, d), true, 'uniques still beam')
local tiered = L.normalize({ highlight = 0, tier = 6 })
eq(LB.wants({ r = 1, t = 7, g = 'equipment' }, tiered, d), true, 'a modifier tier the filter glows for')

local b = LB.beamOf({ gear(3), gear(6), gear(2) }, filter, d)
eq(b.group, 'orange', 'the best item inside wins (an old Exotic is Legendary)')
eq(b.color, LB.GROUPS.orange.color, 'its colour')
eq(b.height, LB.HEIGHTS.normal * LB.GROUPS.orange.height, 'height = setting x group share')
eq(b.intensity, LB.INTENSITIES.normal, 'intensity from the setting')
eq(LB.beamOf({ gear(6), { u = 1 } }, filter, d).group, 'unique', 'a unique wins over rarity')
eq(LB.beamOf({ gear(1), gear(2) }, filter, d), nil, 'nothing the filter glows for: no beam')
eq(LB.beamOf({ gear(5) }, filter, LB.normalize({ height = 'tall', intensity = 'soft' })).height,
  LB.HEIGHTS.tall * LB.GROUPS.orange.height, 'tall')
eq(LB.beamOf(nil, filter, d), nil, 'no items')

-- ---------------------------------------------------------------- lifecycle: server messages
local st = LB.newState()
local player = { x = 100, y = 100, z = 7 }
eq(LB.onBeam(st, { k = 1, p = { 101, 100, 7 }, i = { { r = 7, g = 'equipment' }, { r = 3, g = 'equipment' } } }), true, 'beam starts')
local want = LB.resolve(st, filter, d, player)
eq(count(want), 1, 'one beam')
eq(want['101,100,7'].group, 'orange', 'Mythic is Legendary orange')
eq(LB.onBeam(st, { k = 1, p = { 101, 100, 7 }, i = { { r = 3, g = 'equipment' } } }), true, 'the Mythic was looted')
eq(LB.resolve(st, filter, d, player)['101,100,7'].group, 'blue', 'the beam turns to the next best (Magic blue)')
eq(LB.onBeam(st, { k = 1, p = { 101, 100, 7 }, i = {} }), true, 'looted empty')
eq(count(LB.resolve(st, filter, d, player)), 0, 'the beam is gone')
eq(LB.onBeam(st, { k = 1, i = {} }), false, 'ending an unknown beam changes nothing')
eq(LB.onBeam(st, { k = 'x' }), false, 'bad kill id')
eq(LB.onBeam(st, 'junk'), false, 'not a table')
eq(LB.onBeam(st, { k = 2, p = { 1, 2 }, i = { gear(5) } }), false, 'a bad position is no beam')
LB.onBeam(st, { k = 3, p = { 105, 100, 6 }, i = { gear(15) } })
eq(count(LB.resolve(st, filter, d, player)), 0, 'another floor: not drawn')
eq(count(LB.resolve(st, filter, LB.normalize({ enabled = false }), player)), 0, 'switched off')
eq(count(LB.resolve(st, filter, d, nil)), 0, 'no player position yet')

-- two corpses on one tile: the better one
st = LB.newState()
LB.onBeam(st, { k = 1, p = { 100, 101, 7 }, i = { gear(5) } })
LB.onBeam(st, { k = 2, p = { 100, 101, 7 }, i = { gear(10) } })
eq(LB.resolve(st, filter, d, player)['100,101,7'].group, 'divine', 'one beam per tile, the best corpse')

-- ground items (game_groundlabels rows); corpse rows are the server's beams, not these
LB.setGround(st, { { pos = { x = 99, y = 99, z = 7 }, rows = { { r = 5, g = 'equipment' }, { k = 1, i = {} } } },
  { pos = { x = 98, y = 99, z = 7 }, rows = { { g = 'other' } } }, 'junk' })
want = LB.resolve(st, filter, d, player)
eq(want['99,99,7'] ~= nil, true, 'an item on the ground beams')
eq(want['98,99,7'], nil, 'a plain item does not')
eq(LB.resolve(st, filter, LB.normalize({ ground = false }), player)['99,99,7'], nil, 'ground beams off')
LB.setGround(st, {})
eq(LB.resolve(st, filter, d, player)['99,99,7'], nil, 'picked up: gone')

-- ---------------------------------------------------------------- an AoE kill: many corpses, the cap
st = LB.newState()
for i = 1, 40 do
  LB.onBeam(st, { k = i, p = { 100 + (i % 8) - 4, 100 + math.floor(i / 8) - 2, 7 }, i = { gear(3 + (i % 3)) } })
end
LB.onBeam(st, { k = 99, p = { 110, 110, 7 }, i = { { u = 1 } } })
want = LB.resolve(st, filter, d, player, 10)
eq(count(want), 10, 'capped')
eq(want['110,110,7'] ~= nil, true, 'a far unique is kept over near blue ones')
local groupsKept = {}
for _, w in pairs(want) do groupsKept[w.group] = (groupsKept[w.group] or 0) + 1 end
eq(groupsKept.blue, nil, 'the cap drops the lowest colour first')
eq(count(LB.resolve(st, filter, d, player)), LB.MAX_BEAMS, 'the default cap')

-- ---------------------------------------------------------------- engine calls
local drawn = {}
st = LB.newState()
LB.onBeam(st, { k = 1, p = { 101, 100, 7 }, i = { gear(5) } })
LB.onBeam(st, { k = 2, p = { 102, 100, 7 }, i = { gear(7) } })
local calls
calls, drawn = LB.diff(drawn, LB.resolve(st, filter, d, player))
eq(#calls.set, 2, 'two beams set')
eq(#calls.remove, 0, 'nothing to remove')
calls, drawn = LB.diff(drawn, LB.resolve(st, filter, d, player))
eq(#calls.set + #calls.remove, 0, 'no change: no engine call')
LB.onBeam(st, { k = 1, p = { 101, 100, 7 }, i = {} })
LB.onBeam(st, { k = 2, p = { 102, 100, 7 }, i = { gear(3) } })
calls, drawn = LB.diff(drawn, LB.resolve(st, filter, d, player))
eq(#calls.remove, 1, 'the looted one is removed')
eq(calls.remove[1].x, 101, 'by its position')
eq(#calls.set, 1, 'the changed one is set again')
eq(calls.set[1].color, LB.GROUPS.blue.color, 'in its new colour')
calls, drawn = LB.diff(drawn, LB.resolve(st, filter, LB.normalize({ intensity = 'bright' }), player))
eq(#calls.set, 1, 'a new intensity resets the beam')
calls, drawn = LB.diff(drawn, {})
eq(#calls.remove, 1, 'all off')
eq(count(drawn), 0, 'nothing drawn')

-- ---------------------------------------------------------------- filter fingerprint
eq(LB.filterKey(L.defaults()) ~= LB.filterKey(strict), true, 'a filter change is seen')
eq(LB.filterKey(nil), '', 'no filter')

print(string.format('lootbeams: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
