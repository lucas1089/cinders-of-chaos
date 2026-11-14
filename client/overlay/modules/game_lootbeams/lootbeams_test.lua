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

-- ---------------------------------------------------------------- pair 36 beam effects
-- the ids are the beam_* effects of the server ids file (same repository); one per group, all different
local ids = {}
local f = io.open(dir .. '../../../../server/data/lib/chaos_pack36_fx_ids.lua', 'r')
if f then
  for name, id in f:read('*a'):gmatch('\nChaosVfx%.([%w_]+) = {id = (%d+)') do ids[name] = tonumber(id) end
  f:close()
end
local seen = {}
for _, g in ipairs(LB.GROUP_ORDER) do
  local id = LB.effectFor(g)
  eq(id ~= nil, true, 'group ' .. g .. ' has a beam effect')
  eq(id, ids[LB.EFFECT_NAMES[g]], 'group ' .. g .. ' is ' .. LB.EFFECT_NAMES[g] .. ' of chaos_pack36_fx_ids.lua')
  eq(seen[id or -1], nil, 'group ' .. g .. ' has its own effect')
  if id then seen[id] = true end
end
eq(LB.EFFECT_MS > 1000, true, 'one play of a beam lasts over a second')
eq(LB.effectFor('nothing'), nil, 'no group, no effect')
st = LB.newState()
LB.onBeam(st, { k = 1, p = { 101, 100, 7 }, i = { gear(5) } })
LB.onBeam(st, { k = 2, p = { 102, 100, 7 }, i = { gear(3) } })
calls, drawn = LB.diff({}, LB.resolve(st, filter, d, player))
local pulse = LB.pulse(drawn)
eq(#pulse, 2, 'every drawn beam is added again')
eq(pulse[1].pos.x, 101, 'in tile order')
eq(pulse[1].id, LB.EFFECTS.orange, 'a Legendary beam')
eq(pulse[2].id, LB.EFFECTS.blue, 'a Rare beam')

-- pair 65: a beam at full size (3 x 5 tiles) is added at the tile + (1, 1), the halved 1 x 2 one on the tile
local on = { x = 100, y = 200, z = 7 }
local big = LB.effectPos(on, 3, 5)
eq(big.x == 101 and big.y == 201 and big.z == 7, true, 'a 3 x 5 beam is added one tile south-east')
eq(on.x == 100 and on.y == 200, true, 'the position is not changed')
eq(LB.effectPos(on, 1, 2), on, 'a 1 x 2 beam (pair 36 to 64) is added on its tile')
eq(LB.effectPos(on, nil, nil), on, 'no size read: on the tile')
eq(LB.effectPos(on, 3, 4), on, 'any other size: on the tile')
eq(LB.effectPos(nil, 3, 5), nil, 'no position, no position')
-- the offset is the one the strips are cut for: the item's tile is column w - 1 - dx, row h - 1 - dy of the group
eq(LB.FULL_SIZE.w - 1 - LB.FULL_SIZE.dx, 1, 'the item tile is column 1 of the 3 wide group')
eq(LB.FULL_SIZE.h - 1 - LB.FULL_SIZE.dy, 3, 'the item tile is row 3 of the 5 high group')
do
  local specs = {}
  local sf = io.open(dir .. '../../../tools/sprites/art_import/pack36_beam.csv', 'r')
  if sf then
    for line in sf:lines() do
      local name, w, h, dx, dy = line:match('^effect,([%w_]+),[^,]*,(%d+),(%d+),%d+,%d+,(%d+),(%d+),')
      if name then specs[name] = { tonumber(w), tonumber(h), tonumber(dx), tonumber(dy) } end
    end
    sf:close()
    for _, g in ipairs(LB.GROUP_ORDER) do
      local sp = specs[LB.EFFECT_NAMES[g]]
      eq(sp ~= nil, true, 'the beam spec has ' .. LB.EFFECT_NAMES[g])
      if sp then
        eq(sp[1] == LB.FULL_SIZE.w and sp[2] == LB.FULL_SIZE.h and sp[3] == LB.FULL_SIZE.dx and sp[4] == LB.FULL_SIZE.dy, true,
          LB.EFFECT_NAMES[g] .. ' is cut at the size and offset the module adds it for')
      end
    end
  end
end

-- ---------------------------------------------------------------- filter fingerprint
eq(LB.filterKey(L.defaults()) ~= LB.filterKey(strict), true, 'a filter change is seen')
eq(LB.filterKey(nil), '', 'no filter')

-- ---------------------------------------------------------------- the beam pictures (O569)
-- style: a | b | c, a is the default, anything else folds to it
eq(LB.defaults().style, 'a', 'style a by default')
eq(LB.normalize({ style = 'B' }).style, 'b', 'a style is read in any case')
eq(LB.normalize({ style = 'c' }).style, 'c', 'style c')
eq(LB.normalize({ style = 'zzz' }).style, 'a', 'an unknown style folds to a')
eq(LB.normalize({ style = 5 }).style, 'a', 'a number is no style')
eq(LB.normalize(nil).style, 'a', 'nil: style a')
eq(#LB.STYLE_ORDER, 3, 'three styles')
for _, st in ipairs(LB.STYLE_ORDER) do eq(LB.STYLES[st], true, 'style ' .. st .. ' is known') end

-- paths and clips
eq(LB.artPath('a', 'orange'), '/modules/game_lootbeams/images/a_orange.png', 'art path')
eq(LB.artPath('C', 'unique'), '/modules/game_lootbeams/images/c_unique.png', 'art path of style c')
eq(LB.artPath('x', 'white'), '/modules/game_lootbeams/images/a_white.png', 'an unknown style draws style a')
eq(LB.artPath('a', 'purple'), nil, 'no strip for an unknown group')
eq(LB.clip(0), '0 0 64 128', 'clip of frame 0')
eq(LB.clip(7), '448 0 64 128', 'clip of frame 7')

-- the strips the generator wrote are the size the logic assumes, in every style and group; the colours of the generator are
-- the rarity colours of this module
local function pngSize(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local h = f:read(24)
  f:close()
  if not h or #h < 24 or h:sub(2, 4) ~= 'PNG' then return nil end
  local function u32(str) local a, b, c, d2 = str:byte(1, 4); return ((a * 256 + b) * 256 + c) * 256 + d2 end
  return u32(h:sub(17, 20)), u32(h:sub(21, 24))
end
local A = LB.ART
local frames = A.burst + A.loop
for _, st in ipairs(LB.STYLE_ORDER) do
  for _, g in ipairs(LB.GROUP_ORDER) do
    local w, h = pngSize(dir .. LB.artPath(st, g):gsub('^/modules/game_lootbeams/', ''))
    eq(w, frames * A.w, st .. '_' .. g .. ': strip width is 18 frames of 64 px')
    eq(h, A.h, st .. '_' .. g .. ': strip height is 128 px')
  end
end
do
  local gf = io.open(dir .. '../../../tools/gen_lootbeam_art.py', 'r')
  if gf then
    local src = gf:read('*a')
    gf:close()
    for _, g in ipairs(LB.GROUP_ORDER) do
      local color = src:match("\n    '" .. g .. "': +dict%(color='(#%x+)'")
      eq(color, LB.GROUPS[g].color, 'the generator draws ' .. g .. ' in the rarity colour')
    end
    eq(tonumber(src:match('\nBURST, LOOP = (%d+), %d+')), A.burst, 'the generator has the burst frames of LB.ART')
    eq(tonumber(src:match('\nBURST, LOOP = %d+, (%d+)')), A.loop, 'the generator has the loop frames of LB.ART')
    eq(tonumber(src:match('\nW, H = (%d+), %d+')), A.w, 'the generator frame width')
    eq(tonumber(src:match('\nW, H = %d+, (%d+)')), A.h, 'the generator frame height')
    eq(tonumber(src:match('\nFOOT_X, FOOT_Y = [%d.]+, ([%d.]+)')), A.footY, 'the generator foot row')
  end
end

-- the frame to show: the burst once, then the loop; a standing beam stays on one loop frame
eq(LB.frame(0, true), 0, 'the burst starts at frame 0')
eq(LB.frame(A.burstMs - 1, true), 0, 'still frame 0')
eq(LB.frame(A.burstMs, true), 1, 'frame 1')
eq(LB.frame(LB.ART_MS - 1, true), A.burst - 1, 'the last burst frame')
eq(LB.frame(LB.ART_MS, true), A.burst, 'the loop starts after the burst')
eq(LB.frame(LB.ART_MS + A.loop * A.loopMs, true), A.burst, 'the loop comes round')
eq(LB.frame(LB.ART_MS + 5 * A.loopMs + 3, true), A.burst + 5, 'a frame of the loop')
eq(LB.frame(-50, true), 0, 'a clock step back is frame 0')
eq(LB.frame(nil, true), 0, 'no age is frame 0')
for age = 0, 20000, 37 do
  local f = LB.frame(age, true)
  eq(f >= 0 and f < frames, true, 'a frame is in the strip (' .. age .. ')')
  local still = LB.frame(age, false)
  eq(still, A.burst + A.simple, 'a standing beam never moves (' .. age .. ')')
end
eq(A.simple >= 0 and A.simple < A.loop, true, 'the still frame is a loop frame')

-- size and margins: the foot of the picture lies on the item's tile, whatever the zoom
local w64, h64, ml64, mt64 = LB.box(64, 64, 'normal')
eq(w64, 128, 'a 64 px tile: the picture is twice as wide')
eq(h64, 256, 'a 64 px tile: and twice as high')
eq(ml64, 0, 'a 64 px tile is centred by a zero margin')
for _, tile in ipairs({ 24, 32, 48, 64, 96 }) do
  local w, h, ml, mt = LB.box(tile, tile, 'normal')
  local centreX = 32 + ml -- the engine puts the widget centre at tile corner + 32 + margin
  local centreY = 32 + mt                 -- the widget's centre, from the tile's corner
  local footY = centreY - h / 2 + A.footY * (h / A.h) -- the picture's foot row on the screen
  local wantY = tile / 2 + A.footDrop * tile / A.tile -- the tile's centre plus the drop
  eq(math.abs(footY - wantY) <= 1.5, true, 'the foot of the beam is on the tile at ' .. tile .. ' px (' .. footY .. ' vs ' .. wantY .. ')')
  eq(math.abs(centreX - (tile / 2)) <= 1.5, true, 'the beam is centred on the tile at ' .. tile .. ' px')
  eq(math.abs(w / h - A.w / A.h) < 0.02, true, 'the picture keeps its shape at ' .. tile .. ' px')
end
local ws, hs = LB.box(64, 64, 'short')
local wt, ht = LB.box(64, 64, 'tall')
eq(hs < h64 and h64 < ht, true, 'the height setting scales the picture')
eq(ws < w64 and w64 < wt, true, 'and its width with it (the ring keeps its shape)')
local wu = LB.box(64, 64, 'enormous')
eq(wu, w64, 'an unknown height is normal')
local w0 = LB.box(0, nil, 'normal')
eq(w0, w64, 'no tile size: 64 px tiles')
eq(LB.OPACITY.soft < LB.OPACITY.normal and LB.OPACITY.normal < LB.OPACITY.bright, true, 'intensity is the opacity')
eq(LB.OPACITY.bright, 1.0, 'bright is full opacity')
for _, k in ipairs(LB.INTENSITY_ORDER) do eq(LB.OPACITY[k] ~= nil, true, 'opacity of ' .. k) end
for _, k in ipairs(LB.HEIGHT_ORDER) do eq(LB.HEIGHT_SCALE[k] ~= nil, true, 'scale of ' .. k) end

-- the cap: the best RICH_CAP beams animate, the others stand still (the same order as the choice of the beams)
do
  local want = {}
  for i = 1, 20 do
    local key = 'k' .. string.format('%02d', i)
    want[key] = { group = (i <= 3) and 'orange' or 'white', dist = i, key = key }
  end
  want.kU = { group = 'unique', dist = 30, key = 'kU' }
  local rich = LB.richKeys(want, LB.RICH_CAP)
  local n = 0
  for _ in pairs(rich) do n = n + 1 end
  eq(n, LB.RICH_CAP, 'RICH_CAP beams animate')
  eq(rich.kU, true, 'a Unique beam animates however far')
  eq(rich.k01 and rich.k02 and rich.k03, true, 'then the Legendary ones')
  eq(rich.k04, true, 'then the nearest of the rest')
  eq(rich.k09, nil, 'a far common beam stands still')
  eq(rich.k20, nil, 'the farthest stands still')
  local all = LB.richKeys(want, 100)
  n = 0
  for _ in pairs(all) do n = n + 1 end
  eq(n, 21, 'a cap above the count animates them all')
  eq(next(LB.richKeys({}, 8)), nil, 'no beams, none animate')
  eq(LB.RICH_CAP < LB.MAX_BEAMS, true, 'more beams stand than animate')
  eq(LB.RICH_CAP, 8, 'eight animated beams')
  -- a real resolve with 30 corpses: at most MAX_BEAMS drawn, RICH_CAP of them animate
  local st2 = LB.newState()
  for i = 1, 30 do
    LB.onBeam(st2, { k = 500 + i, p = { 100 + i % 7, 200 + math.floor(i / 7), 7 }, i = { gear(5) } })
  end
  local res = LB.resolve(st2, filter, d, player, LB.MAX_BEAMS)
  eq(count(res), LB.MAX_BEAMS, 'a big pull draws MAX_BEAMS beams')
  eq(count(LB.richKeys(res, LB.RICH_CAP)), LB.RICH_CAP, 'and animates RICH_CAP of them')
end

print(string.format('lootbeams: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
