-- Run from the repo root: luajit client/overlay/modules/game_combatdecals/combatdecals_test.lua (and lua5.3)
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/combatdecals_logic.lua')
local CD = CombatDecalsLogic

local fails = 0
local function eq(a, b, msg)
  if a ~= b then
    fails = fails + 1
    print('FAIL ' .. msg .. ': got ' .. tostring(a) .. ', want ' .. tostring(b))
  end
end
local function near(a, b, msg) eq(a ~= nil and math.abs(a - b) < 1e-6, true, msg .. ' (' .. tostring(a) .. ' vs ' .. tostring(b) .. ')') end

-- the 8-bit palette colours of the server's combat colours (Color::from8bit: r = i/36, g = i/6, b = i, each % 6 * 51)
local function pal(i)
  return string.format('#%02x%02x%02x', (math.floor(i / 36) % 6) * 51, (math.floor(i / 6) % 6) * 51, (i % 6) * 51)
end
eq(CD.kindOfColor(pal(198)), 'fire', 'orange is fire')
eq(CD.kindOfColor(pal(30)), 'poison', 'light green is poison / earth')
eq(CD.kindOfColor(pal(35)), 'ice', 'cyan is ice')
eq(CD.kindOfColor(pal(180)), nil, 'red is physical')
eq(CD.kindOfColor(pal(155)), nil, 'purple is energy')
eq(CD.kindOfColor(pal(5)), nil, 'blue is drowning / mana')
eq(CD.kindOfColor(pal(210)), nil, 'yellow is holy')
eq(CD.kindOfColor(pal(215)), nil, 'white')
eq(CD.kindOfColor(pal(0)), nil, 'black')
eq(CD.kindOfColor('#ff9900ff'), 'fire', 'with alpha')
eq(CD.kindOfColor({ r = 255, g = 153, b = 0 }), 'fire', 'table 0-255')
eq(CD.kindOfColor({ 0, 1, 0 }), 'poison', 'array 0-1')
eq(CD.kindOfColor({ r = 0.0, g = 1.0, b = 1.0 }), 'ice', 'fields 0-1')
eq(CD.kindOfColor(nil), nil, 'nil')
eq(CD.kindOfColor('junk'), nil, 'junk string')
eq(CD.kindOfColor(42), nil, 'number')
eq(CD.kindOfColor({}), nil, 'empty table')
eq(CD.kindOfColor(setmetatable({}, { __index = function() error('boom') end })), nil, 'throwing object')

-- hitKind
eq(CD.hitKind(21, 0, 50, pal(198)), 'fire', 'dealt fire hit')
eq(CD.hitKind(22, 1, 50, pal(35)), 'ice', 'received critical ice')
eq(CD.hitKind(25, 2, 5, pal(30)), 'poison', 'poison tick')
eq(CD.hitKind(20, 0, 50, pal(198)), nil, 'not a damage mode')
eq(CD.hitKind(21, 3, 50, pal(198)), nil, 'mana drain number')
eq(CD.hitKind(21, 5, 50, pal(198)), nil, 'shield number')
eq(CD.hitKind(21, 0, 0, pal(198)), nil, 'zero value')
eq(CD.hitKind(21, 0, 50, pal(180)), nil, 'physical')
eq(CD.hitKind(21, nil, 50, pal(198)), 'fire', 'type defaults to plain')

-- blood
eq(CD.bleeds('Rotworm'), true, 'worm bleeds')
eq(CD.bleeds('Skeleton Warrior'), false, 'skeleton')
eq(CD.bleeds('Fire Elemental'), false, 'elemental')
eq(CD.bleeds('Stone GOLEM'), false, 'golem upper case')
eq(CD.bleeds(nil), true, 'no name')
eq(CD.bleeds(''), true, 'empty name')

-- life and fade
eq(CD.lifeFor(0), 20000, 'life min')
eq(CD.lifeFor(0.5), 25000, 'life mid')
eq(CD.lifeFor(1), 29999, 'life stays under max')
eq(CD.lifeFor(-3), 20000, 'life clamps low')
eq(CD.lifeFor(nil), 20000, 'life nil')
near(CD.alphaAt(0, 24000), CD.START, 'start')
near(CD.alphaAt(24000 * CD.HOLD, 24000), CD.START, 'end of hold')
eq(CD.alphaAt(24000, 24000), nil, 'gone at the end')
eq(CD.alphaAt(99999, 24000), nil, 'gone after')
eq(CD.alphaAt(-5, 24000), CD.START, 'negative age')
eq(CD.alphaAt(10, 0), nil, 'no life')
do
  local prev = CD.START + 1
  local mono = true
  for age = 0, 23990, 10 do
    local a = CD.alphaAt(age, 24000)
    if a > prev + 1e-9 or a < 0 or a > CD.START then mono = false end
    prev = a
  end
  eq(mono, true, 'alpha never rises and stays in range')
  local half = CD.alphaAt(24000 * (CD.HOLD + (1 - CD.HOLD) / 2), 24000)
  near(half, CD.START / 2, 'half way of the fade')
end

-- caps
do
  local st = CD.newState()
  eq(CD.mayAdd(st, 'fire', 1000), true, 'first hit stain')
  CD.add(st, { kind = 'fire', born = 1000, life = 22000 })
  eq(CD.mayAdd(st, 'ice', 1100), false, 'inside the gap')
  eq(CD.mayAdd(st, 'ice', 1000 + CD.HIT_GAP_MS), true, 'after the gap')
  eq(CD.mayAdd(st, 'blood', 1001), true, 'blood ignores the gap')
  CD.add(st, { kind = 'blood', born = 1001, life = 22000 })
  eq(st.lastHit, 1000, 'blood does not move the hit clock')
  for i = 1, CD.MAX - 2 do CD.add(st, { kind = 'blood', born = 1002, life = 22000 }) end
  eq(#st.decals, CD.MAX, 'filled to the cap')
  eq(CD.mayAdd(st, 'fire', 99999), false, 'hit stain waits when full')
  eq(CD.mayAdd(st, 'blood', 99999), true, 'blood may push')
  eq(#CD.evictions(st), 1, 'one eviction at the cap')
  eq(CD.evictions(st)[1], 1, 'the oldest goes')
  table.remove(st.decals, 1)
  eq(#CD.evictions(st), 0, 'room: none')
end

-- step
do
  local st = CD.newState()
  CD.add(st, { kind = 'blood', born = 0, life = 20000 })
  CD.add(st, { kind = 'fire', born = 5000, life = 25000 })
  local alive, gone = CD.step(st, 21000)
  eq(#alive, 1, 'one alive')
  eq(#gone, 1, 'one gone')
  eq(alive[1].kind, 'fire', 'the younger stays')
  eq(alive[1].alpha ~= nil, true, 'alpha written')
  eq(#st.decals, 1, 'state keeps the alive ones')
  alive, gone = CD.step(st, 40000)
  eq(#alive + #st.decals, 0, 'all gone later')
  eq(#gone, 1, 'last one reported')
end

-- on screen
do
  local c = { x = 100, y = 100, z = 7 }
  eq(CD.onScreen({ x = 107, y = 105, z = 7 }, c, 15, 11), true, 'edge of 15x11')
  eq(CD.onScreen({ x = 108, y = 100, z = 7 }, c, 15, 11), false, 'one past in x')
  eq(CD.onScreen({ x = 100, y = 106, z = 7 }, c, 15, 11), false, 'one past in y')
  eq(CD.onScreen({ x = 100, y = 100, z = 6 }, c, 15, 11), false, 'other floor')
  eq(CD.onScreen(nil, c, 15, 11), false, 'no position')
  eq(CD.onScreen(c, c, 0, 0), false, 'no size')
end

-- tile choice
do
  local taken = { ['10,10'] = true }
  local function free(p) return not taken[p.x .. ',' .. p.y] end
  local p = CD.pickTile({ x = 5, y = 5, z = 7 }, free, 0, nil)
  eq(p.x .. ',' .. p.y, '5,5', 'own tile when free')
  eq(CD.pickTile({ x = 10, y = 10, z = 7 }, free, 0, nil), nil, 'taken, no spread')
  local q = CD.pickTile({ x = 10, y = 10, z = 7 }, free, CD.SPREAD, function() return 0 end)
  eq(q ~= nil and q.z, 7, 'neighbour on the same floor')
  eq(q.x == 10 and q.y == 9, true, 'first neighbour north with rnd 0')
  local none = CD.pickTile({ x = 10, y = 10, z = 7 }, function() return false end, CD.SPREAD, function() return 0.5 end)
  eq(none, nil, 'nothing free')
  local tries = 0
  CD.pickTile({ x = 1, y = 1, z = 7 }, function() tries = tries + 1 return false end, CD.SPREAD, function() return 0 end)
  eq(tries <= 1 + CD.SPREAD * 4, true, 'bounded tries')
end

-- sizes and pictures
do
  local w, h = CD.tileSize(960, 704, 15, 11, false)
  eq(w, 64, 'tile width'); eq(h, 64, 'tile height')
  w, h = CD.tileSize(1000, 600, 15, 11, true)
  eq(w, h, 'square with keep aspect')
  w, h = CD.tileSize(nil, 600, 15, 11, true)
  eq(w, 64, 'no rect: default')
  local size, ml, mt = CD.box(64, 64, 32)
  eq(size, 64, 'box size'); eq(ml, 0, 'margin left'); eq(mt, 0, 'margin top')
  size, ml = CD.box(128, 96, 64)
  eq(size, 96, 'box uses the smaller side'); eq(ml, 0, 'margin for 2x sprites')
  eq(CD.path('blood', 2), '/modules/game_combatdecals/images/blood2', 'path blood 2')
  eq(CD.path('fire', 1), '/modules/game_combatdecals/images/scorch1', 'path scorch')
  eq(CD.path('ice', 9), '/modules/game_combatdecals/images/frost1', 'bad variant falls back')
  eq(CD.path('poison', nil), '/modules/game_combatdecals/images/stain1', 'path stain')
  eq(CD.path('holy', 1), nil, 'unknown kind')
  eq(CD.rotation(0), 0, 'rot 0'); eq(CD.rotation(0.3), 90, 'rot 90'); eq(CD.rotation(0.99), 270, 'rot 270')
end

-- option
eq(CD.optionOn(true), true, 'on'); eq(CD.optionOn(false), false, 'off'); eq(CD.optionOn(nil), true, 'default on')
eq(CD.optionOn('false'), true, 'junk gives the default')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('combatdecals_test: OK')
