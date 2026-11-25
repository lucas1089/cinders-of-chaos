-- luajit lootburst_test.lua && lua5.3 lootburst_test.lua (from any folder)
-- Loot burst rules (lootburstlogic.lua, O677): the server's explode message, the arc of a flight (ease-out along the ground, gravity
-- upwards, the peak of 0.9 tile + 0.25 per tile of distance), the shadow, the trail, the landing, the flashes, frames, sizes and margins,
-- and the pictures the generator wrote.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'lootburstlogic.lua')
local L = LootBurstLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function near(a, b, tol, what)
  checks = checks + 1
  if type(a) ~= 'number' or math.abs(a - b) > tol then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' vs ' .. tostring(b)); fails = fails + 1 end
end
local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- ---------------------------------------------------------------- the message
local msg = { o = { 100, 100, 7 }, k = 55, f = {
  { id = 3031, c = 120, to = { 101, 100, 7 }, d = 0, fl = 230 },
  { id = 3264, c = 1, to = { 98, 102, 7 }, d = 60, fl = 300, g = 'orange' },
  { id = 3265, c = 1, to = { 102, 99, 7 }, d = 130, fl = 330, g = 'divine' },
  { id = 3266, c = 1, to = { 100, 98, 7 }, d = 200, fl = 330, g = 'set' },
  { id = 3267, c = 1, to = { 101, 101, 7 }, d = 270, fl = 400, g = 'unique' },
} }
local b = L.parse(msg)
eq(b ~= nil, true, 'a good message parses')
eq(b.origin.x == 100 and b.origin.y == 100 and b.origin.z == 7, true, 'the death tile')
eq(b.kill, 55, 'the kill id')
eq(#b.flights, 5, 'five flights')
eq(b.flights[1].dx, 1, 'the landing offset')
eq(b.flights[2].dx == -2 and b.flights[2].dy == 2, true, 'a negative offset')
eq(b.flights[2].dist, 2, 'the distance is the larger offset')
eq(b.flights[1].group, nil, 'no group: plain')
eq(b.flights[5].group, 'unique', 'the group is kept')
eq(b.flights[1].count, 120, 'the count')
eq(b.best, 'unique', 'the best group of the kill')
eq(b.flights[5].landAt, 670, 'the landing time is delay + flight')
eq(b.flights[5].endAt, 670 + L.HOLD_MS, 'the widget goes HOLD_MS after it')
eq(b.endMs, 670 + L.HOLD_MS + L.EFFECT_GRACE_MS, 'the burst ends after the last landing effects')
eq(L.parse(nil), nil, 'no message')
eq(L.parse('junk'), nil, 'junk')
eq(L.parse({ o = { 1, 2, 3 } }), nil, 'no flights')
eq(L.parse({ f = {} }), nil, 'no origin')
eq(L.parse({ o = { 1, 2 }, f = { { id = 1, to = { 1, 2, 3 } } } }), nil, 'a bad origin')
eq(L.parse({ o = { 1, 2, 3 }, f = {} }), nil, 'an empty list')
local odd = L.parse({ o = { 100, 100, 7 }, f = {
  { id = 5, c = 0, to = { 101, 100, 7 }, d = -9, fl = 99999, g = 'red' },     -- clamped, an unknown group is none
  { id = 0, to = { 101, 100, 7 }, fl = 100 },                                 -- no item
  { id = 6, to = { 101, 100, 8 }, fl = 100 },                                 -- another floor
  { id = 7, to = { 110, 100, 7 }, fl = 100 },                                 -- too far
  { id = 8 },                                                                 -- no tile
  'junk',
  { id = 9, c = 'x', to = { 100, 100, 7 }, d = 99999999, fl = 1 },            -- on the death tile itself, clamped
} })
eq(#odd.flights, 2, 'bad flights are dropped')
eq(odd.flights[1].count, 1, 'a count of 0 is 1')
eq(odd.flights[1].d, 0, 'a negative delay is 0')
eq(odd.flights[1].fl, L.MAX_FLIGHT_MS, 'a long flight is clamped')
eq(odd.flights[1].group, nil, 'an unknown group is none')
eq(odd.flights[2].d, L.MAX_DELAY_MS, 'a late start is clamped')
eq(odd.flights[2].fl, L.MIN_FLIGHT_MS, 'a flight of 1 ms is the minimum')
eq(odd.flights[2].dist, 0, 'a landing on the death tile has distance 0')
eq(odd.flights[2].peak > 0, true, 'and still an arc (distance counts as 1)')
local many = { o = { 100, 100, 7 }, f = {} }
for i = 1, 30 do many.f[i] = { id = 100 + i, to = { 101, 100, 7 }, d = i, fl = 200 } end
eq(#L.parse(many).flights, L.MAX_FLIGHTS, 'at most 14 flights')
eq(L.parse({ o = { x = 5, y = 6, z = 7 }, f = { { id = 3, to = { x = 6, y = 6, z = 7 }, fl = 100 } } }).flights[1].dx, 1, 'positions as objects')

-- ---------------------------------------------------------------- the peak: 0.9 tile and 0.25 per tile, the drama by group
near(L.peak(1, 'orange'), 0.9 + 0.25, 1e-9, 'the peak of a Legendary item at one tile')
near(L.peak(2, 'orange'), 0.9 + 0.5, 1e-9, 'and at two tiles')
eq(L.peak(2, nil) < L.peak(2, 'orange'), true, 'a plain item flies lower')
eq(L.peak(2, 'orange') < L.peak(2, 'divine') and L.peak(2, 'divine') > L.peak(2, 'orange'), true, 'Divine higher than Legendary')
eq(L.peak(2, 'unique') > L.peak(2, 'divine') and L.peak(2, 'unique') > L.peak(2, 'set'), true, 'a unique flies highest')
eq(L.peak(0, nil), L.peak(1, nil), 'distance 0 counts as 1')
eq(L.peak(3, nil) > L.peak(1, nil), true, 'a farther landing arcs higher')
for _, g in ipairs({ 'orange', 'divine', 'set', 'unique' }) do
  eq(L.styleOf(g).peak >= 1, true, g .. ' flies at the full height or more')
  eq(L.styleOf(g).trail >= 2, true, g .. ' has a trail')
  eq(L.styleOf(g).ring, true, g .. ' has a landing ring')
end
eq(L.styleOf(nil).trail, 0, 'a plain item has no trail')
eq(L.styleOf(nil).ring, false, 'and no ring')
eq(L.styleOf('nonsense'), L.STYLES.plain, 'an unknown group is plain')
eq(L.styleOf('unique').trail > L.styleOf('orange').trail, true, 'the rarer, the longer the trail')
eq(L.styleOf('unique').flash > L.styleOf('divine').flash and L.styleOf('divine').flash > L.styleOf('orange').flash, true, 'the rarer, the bigger the flash')
eq(L.styleOf('unique').launch > 0 and L.styleOf('orange').launch == 0, true, 'only a unique adds a flash of its own')
local orders = {}
for key, s in pairs(L.STYLES) do orders[s.order] = key end
eq(count(orders), 5, 'every group has its own order')
-- the colours are the beam groups' colours
local g = io.open(dir .. '../game_lootbeams/lootbeamslogic.lua', 'r')
if g then
  local src = g:read('*a')
  g:close()
  for key, color in pairs(L.COLORS) do
    eq(src:match("\n  " .. key .. " +=  *{ color = '(#%x+)'"), color, key .. ' is the colour of its beam group')
  end
end
eq(count(L.COLORS), 4, 'four coloured groups')

-- ---------------------------------------------------------------- the arc: ease-out along the ground, gravity upwards
local ex0, h0 = L.arc(0, 1.4)
local ex1, h1 = L.arc(1, 1.4)
eq(ex0 == 0 and h0 == 0, true, 'it leaves the death tile on the ground')
eq(ex1 == 1 and h1 == 0, true, 'and lands on the ground')
local exM, hM = L.arc(0.5, 1.4)
near(hM, 1.4, 1e-9, 'half way it is at the peak')
eq(exM > 0.5, true, 'ease-out: more than half the way along the ground by half the time')
local prev, prevH, rising, falling = -1, -1, true, false
for i = 0, 100 do
  local ex, h = L.arc(i / 100, 1.4)
  eq(ex >= prev, true, 'the way along the ground never goes back (' .. i .. ')')
  if i <= 50 then eq(h >= prevH, true, 'rising to the peak (' .. i .. ')') else eq(h <= prevH, true, 'falling after it (' .. i .. ')') end
  eq(h >= 0, true, 'never under the ground (' .. i .. ')')
  prev, prevH = ex, h
end
local _, hq = L.arc(0.25, 1.4)
near(hq, 0.75 * 1.4, 1e-9, 'gravity: a parabola in time (a quarter of the time, three quarters of the height)')
eq(select(1, L.arc(-3, 1)), 0, 'time before the start is the start')
eq(select(1, L.arc(7, 1)), 1, 'and after the end is the end')
eq(L.popScale(0) < 0.7, true, 'the item starts small')
eq(L.popScale(0.3) > 1.15, true, 'pops up to 1.2 a third of the way')
near(L.popScale(1), 1.0, 1e-9, 'and is its own size at the landing')
for i = 0, 100 do
  local s = L.popScale(i / 100)
  eq(s > 0.5 and s <= 1.21, true, 'the pop stays in a sane range (' .. i .. ')')
end

-- ---------------------------------------------------------------- the pose of a flight
local f = b.flights[2] -- Legendary, to (-2, +2), d 60, fl 300
eq(L.pose(f, 0).phase, 'wait', 'before its delay it waits')
eq(L.pose(f, 59).phase, 'wait', 'still')
local p0 = L.pose(f, 60)
eq(p0.phase, 'fly', 'it leaves at its delay')
near(p0.x, 0, 1e-9, 'from the death tile')
near(p0.y, 0, 1e-9, 'on the ground')
near(p0.scale, 0.55, 1e-9, 'small')
local pm = L.pose(f, 60 + 150)
eq(pm.phase, 'fly', 'half way')
near(pm.h, f.peak, 1e-9, 'at the peak')
eq(pm.y < pm.gy, true, 'above its ground point (up is negative)')
near(pm.gx, f.dx * (1 - 0.25), 1e-9, 'the ground point by the ease-out')
near(pm.shadow.scale, 0.5, 1e-9, 'the shadow shrinks to half at the apex')
eq(pm.shadow.alpha < 0.55, true, 'and fades a little')
local pe = L.pose(f, 60 + 299)
eq(pe.phase, 'fly', 'the last ms of the flight')
near(pe.x, f.dx, 0.01, 'at its landing tile')
near(pe.y, f.dy, 0.05, 'on the ground')
near(pe.shadow.scale, 1, 0.05, 'the shadow is full size again')
local pl = L.pose(f, 60 + 300)
eq(pl.phase, 'land', 'the flight ends: the hop')
eq(pl.x == f.dx and pl.scale == 1, true, 'on its tile at its own size')
local hop = 0
for a = 0, L.BOUNCE_MS - 1, 5 do
  local p = L.pose(f, 60 + 300 + a)
  hop = math.max(hop, p.h)
  eq(p.phase, 'land', 'the hop is part of the landing (' .. a .. ')')
end
near(hop, f.peak * L.BOUNCE, f.peak * 0.03, 'the hop is about 15% of the arc')
eq(L.pose(f, 60 + 300 + L.HOLD_MS).phase, 'done', 'the widget is done HOLD_MS after the flight ends')
eq(L.pose(f, 60 + 300 + L.HOLD_MS - 1).phase, 'land', 'not before')
eq(L.pose(f, 99999).phase, 'done', 'long after')
eq(L.BOUNCE_MS <= L.HOLD_MS, true, 'the hop fits in the hold')
eq(L.HOLD_MS, 60, 'the widget is removed 60 ms after the flight ends')
eq(L.pose(f, nil).phase, 'wait', 'no age: the start')

-- every pose over the whole life of every flight stays finite and above the ground
for _, fl in ipairs(b.flights) do
  local lastX = -1e9
  for a = 0, fl.endAt + 100, 7 do
    local p = L.pose(fl, a)
    if p.phase ~= 'wait' and p.phase ~= 'done' then
      eq(p.h >= -1e-9, true, 'no pose under the ground')
      eq(p.x == p.x and p.y == p.y, true, 'no NaN')
      eq(p.scale > 0, true, 'a visible size')
      eq(p.shadow.alpha >= 0 and p.shadow.alpha <= 0.62, true, 'the shadow alpha in range')
      eq(p.shadow.scale >= 0.49 and p.shadow.scale <= 1.001, true, 'the shadow scale in range')
    end
  end
end

-- ---------------------------------------------------------------- the trail
local u = b.flights[5]
eq(#L.trail(u, u.d - 1), 0, 'no trail before it leaves')
eq(#L.trail(u, u.d), 0, 'none at the very start')
eq(#L.trail(u, u.d + u.fl + 1), 0, 'none after the landing')
eq(#L.trail(b.flights[1], b.flights[1].d + 100), 0, 'a plain item leaves none')
local tr = L.trail(u, u.d + 300)
eq(#tr, L.styleOf('unique').trail, 'a unique leaves its full trail in the air')
for i = 2, #tr do
  eq(tr[i].alpha < tr[i - 1].alpha, true, 'each glow is fainter than the one before (' .. i .. ')')
  eq(tr[i].size < tr[i - 1].size, true, 'and smaller (' .. i .. ')')
end
local late = L.trail(u, u.d + 40)
eq(#late < #tr, true, 'early in the flight the trail is still short (only what has been flown)')
eq(#L.trail(b.flights[2], b.flights[2].d + 150), L.styleOf('orange').trail, 'a Legendary item leaves two')
-- a glow of the trail lies on the path of the item, behind it
local pp = L.pose(u, u.d + 300)
eq(tr[1].x ~= pp.x or tr[1].y ~= pp.y, true, 'a glow is behind the item, not on it')

-- ---------------------------------------------------------------- the landing and the flashes
eq(L.landing(b.flights[1]).ring, nil, 'a plain item lands with a dust puff and no ring')
eq(L.landing(b.flights[1]).dust > 0, true, 'a puff')
eq(L.landing(b.flights[2]).ring.color, L.COLORS.orange, 'a Legendary item lands with an orange ring')
eq(L.landing(b.flights[3]).ring.color, L.COLORS.divine, 'a Divine one with a divine ring')
eq(L.landing(b.flights[4]).ring.color, L.COLORS.set, 'a set piece with a set ring')
eq(L.landing(b.flights[5]).ring.color, L.COLORS.unique, 'a unique with a unique ring')
eq(L.landing(b.flights[5]).ring.size > L.landing(b.flights[2]).ring.size, true, 'the unique ring is the biggest')
local fl = L.flashes(b)
eq(fl[1].at, 0, 'the first flash is at the start of the kill')
eq(fl[1].tint, L.COLORS.unique, 'in the colour of the best item')
eq(fl[1].size, L.styleOf('unique').flash, 'as big as the best group')
eq(#fl, 2, 'and the unique adds one when it leaves')
eq(fl[2].at, b.flights[5].d, 'at its own launch')
eq(fl[2].size, L.styleOf('unique').launch, 'the strongest flash of all')
eq(fl[2].size > fl[1].size, true, 'stronger than the first')
local plainOnly = L.parse({ o = { 100, 100, 7 }, f = { { id = 1, to = { 101, 100, 7 }, fl = 200 }, { id = 2, to = { 99, 100, 7 }, d = 50, fl = 200 } } })
local pf = L.flashes(plainOnly)
eq(#pf, 1, 'a plain kill has one flash')
eq(pf[1].tint, L.WARM, 'a warm one')
eq(pf[1].size, L.styleOf(nil).flash, 'a small one')
eq(pf[1].size < fl[1].size, true, 'smaller than a unique kill')
local many2 = { o = { 100, 100, 7 }, f = {} }
for i = 1, 10 do many2.f[i] = { id = 100 + i, to = { 101, 100, 7 }, d = i * 10, fl = 200, g = 'unique' } end
eq(#L.flashes(L.parse(many2)) <= 3, true, 'at most three flashes')

-- ---------------------------------------------------------------- frames, sizes, margins
eq(L.frame('flash', 0), 0, 'the flash starts at frame 0')
eq(L.frame('flash', L.ART.flash.ms), 1, 'frame 1')
eq(L.frame('flash', L.duration('flash') - 1), L.ART.flash.frames - 1, 'the last frame')
eq(L.frame('flash', L.duration('flash')), nil, 'played out')
eq(L.frame('ring', -20), 0, 'a clock step back is frame 0')
eq(L.frame('shadow', 99999), 0, 'a still picture is always frame 0')
eq(L.frame('nothing', 0), 0, 'an unknown picture reads as still')
eq(L.duration('dust'), L.ART.dust.frames * L.ART.dust.ms, 'the duration of a strip')
eq(L.duration('nothing'), 0, 'unknown: 0')
eq(L.EFFECT_GRACE_MS >= L.duration('dust') and L.EFFECT_GRACE_MS >= L.duration('ring'), true, 'the grace covers the landing effects')
eq(L.clip('flash', 3), '192 0 64 64', 'the clip of a frame')
eq(L.clip('ring', 2), '128 0 64 40', 'the clip of a ring frame')
eq(L.artPath('flash'), '/modules/game_lootburst/images/flash.png', 'the picture path')
eq(L.artPath('nothing'), nil, 'no such picture')
local w, h = L.size('flash', 1, 32, 32)
eq(w == 64 and h == 64, true, 'the art at a 32 px tile is its own size')
w, h = L.size('flash', 1.5, 64, 64)
eq(w == 192 and h == 192, true, 'scaled to a 64 px tile and by 1.5')
w, h = L.size('glow', 0.5, 0, nil)
eq(w == 24 and h == 24, true, 'no tile size: a 64 px tile (24 * 2 * 0.5)')
local ml, mt = L.margins(32, 32, 0, 0)
eq(ml == -16 and mt == -16, true, 'a 32 px tile: tile / 2 - 32 centres a widget')
ml, mt = L.margins(64, 64, 0, 0)
eq(ml == 0 and mt == 0, true, 'a 64 px tile is centred by a zero margin')
ml, mt = L.margins(64, 64, 1, -1)
eq(ml == 64 and mt == -64, true, 'one tile right and one up')
ml, mt = L.margins(48, 40, 0.5, 0.25)
eq(ml == -8 + 24 and mt == -12 + 10, true, 'half a tile right, a quarter down on a 48 x 40 tile')
-- HD Sprite Upscaling: the engine adds spriteSize 64, not 32 (seen in a client 2026-11-25, V8)
ml, mt = L.margins(64, 64, 0, 0, 64)
eq(ml == -32 and mt == -32, true, 'HD, a 64 px tile: tile / 2 - 64 centres a widget')
ml, mt = L.margins(128, 128, 0, 0, 64)
eq(ml == 0 and mt == 0, true, 'HD, a 128 px tile: no margin')
ml = L.margins(64, 64, 0, 0, 0)
eq(ml, 0, 'no sprite size: 32')
local counts = {}
eq(L.canAdd(counts, 'a', true), true, 'an empty tile takes anything')
counts.a = L.MAX_PER_TILE
eq(L.canAdd(counts, 'a', true), false, 'a full tile takes no extras (trail glows)')
eq(L.canAdd(counts, 'a', false), true, 'but still an item or a shadow')
counts.a = 15
eq(L.canAdd(counts, 'a', false), false, 'the engine keeps 16 per tile: 15 is the most')
eq(L.posKey({ x = 1, y = 2, z = 3 }), '1,2,3', 'the tile key')

-- ---------------------------------------------------------------- the settings
eq(L.enabledOf(nil), true, 'on by default')
eq(L.enabledOf(false), false, 'off')
eq(L.enabledOf('false'), false, 'g_settings strings: false')
eq(L.enabledOf('true'), true, 'true')
eq(L.enabledOf(1), true, '1')
eq(L.capability(true, true).on, 1, 'on and able: the server is told 1')
eq(L.capability(false, true).on, 0, 'off: 0, the stock effects come back')
eq(L.capability(true, false).on, 0, 'a client that cannot draw it: 0')

-- ---------------------------------------------------------------- the pictures the generator wrote
local function pngSize(path)
  local fh = io.open(path, 'rb')
  if not fh then return nil end
  local head = fh:read(24)
  fh:close()
  if not head or #head < 24 or head:sub(2, 4) ~= 'PNG' then return nil end
  local function u32(str) local a, c, d2, e = str:byte(1, 4); return ((a * 256 + c) * 256 + d2) * 256 + e end
  return u32(head:sub(17, 20)), u32(head:sub(21, 24))
end
for _, kind in ipairs(L.ART_ORDER) do
  local a = L.ART[kind]
  local pw, ph = pngSize(dir .. L.artPath(kind):gsub('^/modules/game_lootburst/', ''))
  eq(pw, a.w * a.frames, kind .. ': the strip is ' .. a.frames .. ' frames of ' .. a.w .. ' px wide')
  eq(ph, a.h, kind .. ': ' .. a.h .. ' px high')
end
do
  local gf = io.open(dir .. '../../../tools/gen_lootburst_art.py', 'r')
  if gf then
    local src = gf:read('*a')
    gf:close()
    for kind, a in pairs(L.ART) do
      local w2, h2, n = src:match("\n    '" .. kind .. "': %((%d+), (%d+), (%d+)%)")
      eq(tonumber(w2) == a.w and tonumber(h2) == a.h and tonumber(n) == a.frames, true, 'the generator draws ' .. kind .. ' at the size of ART')
    end
  end
end

print(string.format('lootburst: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
