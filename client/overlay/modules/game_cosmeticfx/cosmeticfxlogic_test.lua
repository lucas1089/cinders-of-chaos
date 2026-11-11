-- luajit client/overlay/modules/game_cosmeticfx/cosmeticfxlogic_test.lua (and lua5.3), from the repo root
dofile('client/overlay/modules/game_cosmeticfx/cosmeticfxlogic.lua')
local CF = CosmeticFxLogic

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end
local function near(a, b, m)
  n = n + 1
  if math.abs(a - b) > 1e-6 then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

-- looks from the server
local l = CF.cleanLook({ f = 'ember', o = 'gold', p = 1 })
eq(l.f, 'ember', 'print art') eq(l.o, 'gold', 'glow art') eq(l.p, true, 'pulse')
eq(CF.cleanLook({ f = '../x' }), nil, 'a path is no art key')
eq(CF.cleanLook({ p = 1 }), nil, 'nothing to draw')
eq(CF.cleanLook({ f = 'ash', p = 1 }).p, nil, 'no pulse without a glow')
local looks = CF.mergeLooks({}, { names = { Bob = { f = 'ember' }, Ann = { o = 'void' } }, full = true })
eq(looks.Bob.f, 'ember', 'full list') eq(looks.Ann.o, 'void', 'full list 2')
looks = CF.mergeLooks(looks, { names = { Bob = false, Cid = { f = 'frost' } } })
eq(looks.Bob, nil, 'false removes') eq(looks.Ann.o, 'void', 'others stay') eq(looks.Cid.f, 'frost', 'added')
looks = CF.mergeLooks(looks, { names = { Zed = { f = 'rime' } }, full = true })
eq(looks.Ann, nil, 'a full list replaces') eq(looks.Zed.f, 'rime', 'the new full list')

-- the local preview wins while it lasts
local preview = { look = { o = 'cinder', p = true }, untilMs = 1000 }
eq(CF.lookOf(looks, 'Me', true, preview, 999).o, 'cinder', 'preview on the local player')
eq(CF.lookOf(looks, 'Me', true, preview, 1000), nil, 'preview over')
eq(CF.lookOf(looks, 'Zed', false, preview, 10).f, 'rime', 'others keep theirs')

-- the settings hide others only
eq(CF.allowed('footprint', { othersFootprints = false }, true), true, 'own prints always')
eq(CF.allowed('footprint', { othersFootprints = false }, false), false, 'others hidden')
eq(CF.allowed('outline', { othersOutlines = false, othersFootprints = true }, false), false, 'outlines hidden')
eq(CF.allowed('outline', nil, false), true, 'defaults show')
eq(CF.hasFlag(16384 + 4, CF.PZ_FLAG), true, 'in a protection zone') eq(CF.hasFlag(4, CF.PZ_FLAG), false, 'not')

-- step directions
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 5, y = 4, z = 7 }), 0, 'north')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }), 90, 'east')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 5, y = 6, z = 7 }), 180, 'south')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 4, y = 5, z = 7 }), 270, 'west')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 6, y = 6, z = 7 }), 135, 'south-east')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 5, y = 4, z = 6 }), nil, 'stairs leave no print')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 9, y = 5, z = 7 }), nil, 'a teleport leaves no print')
eq(CF.stepRotation({ x = 5, y = 5, z = 7 }, { x = 5, y = 5, z = 7 }), nil, 'a turn leaves no print')

-- fading and pulsing
near(CF.printOpacity(0), CF.PRINT_START, 'fresh print')
near(CF.printOpacity(CF.PRINT_LIFE_MS / 2), CF.PRINT_START / 2, 'half way')
eq(CF.printOpacity(CF.PRINT_LIFE_MS), nil, 'gone')
near(CF.pulseOpacity(0), CF.PULSE_LOW, 'pulse low')
near(CF.pulseOpacity(CF.PULSE_MS / 2), 1, 'pulse high')
eq(CF.pulseOpacity(123) >= CF.PULSE_LOW and CF.pulseOpacity(123) <= 1, true, 'pulse in range')

-- limits: the walker's oldest past its own cap, then the oldest overall
local prints = {}
for i = 1, CF.MAX_PER_CREATURE do prints[#prints + 1] = { owner = 1, born = i } end
local drop = CF.evictions(prints, 1)
eq(#drop, 1, 'one of the walker goes') eq(drop[1], 1, 'its oldest')
eq(#CF.evictions(prints, 2), 0, 'another walker drops nothing')
prints = {}
for i = 1, CF.MAX_PRINTS do prints[#prints + 1] = { owner = i, born = i } end
drop = CF.evictions(prints, 'new')
eq(#drop, 1, 'over the screen cap') eq(drop[1], 1, 'the oldest print on screen')

-- sizes
local w, h = CF.tileSize(960, 704, 15, 11, true)
eq(w, 64, 'tile width') eq(h, 64, 'tile height')
eq(CF.glowSize(32), 64, 'glow covers two tiles')
-- O499: this block pinned CF.printBox(64, 64, 32) = 58, 0, 0 and (96, 96, 32) = .., 16, 16: a floor widget sized and
-- moved in SCREEN pixels. A floor widget is drawn in map pixels (base patch 0078 draws it in drawFloor), so at 64 px
-- tiles the print was 1.8 tiles wide and half a tile right and down. The unit is now the sprite size, any zoom.
local hs, hm = CF.hostBox(32, 32)
eq(hs, 96, 'host: 3 x 3 tiles') eq(hm, -16, 'host margin centres it on its tile (default centre is a tile corner)')
local _, hm2 = CF.hostBox(64, 32)
eq(hm2, 0, 'fallback in screen px at 64 px tiles: no margin, as the old print had')
eq(CF.markSize(32, 'foot'), 16, 'a foot mark is half a tile') eq(CF.markSize(32, 'pair'), 29, 'a pair picture is 0.9 tile')
eq(CF.markSize(64, 'foot'), 32, 'scales with the unit')
local mml, mmt = CF.markMargins(32, 16, 16, 16)
eq(mml, 40, 'tile centre: host origin is one tile before the tile') eq(mmt, 40, 'same down')
mml = CF.markMargins(32, 0, 0, 16)
eq(mml, 24, 'tile corner')
eq(CF.markPath('ember', 0), '/modules/game_cosmeticfx/images/marks/ember_l', 'left mark path')
eq(CF.markPath('ember', 1), '/modules/game_cosmeticfx/images/marks/ember_r', 'right mark path')

-- eviction with two marks per step: the walker's cap is in marks (8: four tiles), one call per mark or per step
prints = {}
for i = 1, 8 do prints[#prints + 1] = { owner = 1, born = i } end
eq(#CF.evictions(prints, 1, 2), 2, 'a step of two marks drops the two oldest') eq(CF.evictions(prints, 1, 2)[2], 2, 'the second oldest')
eq(#CF.evictions(prints, 1, 1, 6), 3, 'a smaller cap (soft mode, 6) drops more')
prints = {}
for i = 1, CF.MAX_PRINTS do prints[#prints + 1] = { owner = i, born = i } end
eq(#CF.evictions(prints, 'new', 2), 2, 'two marks past the screen cap push two out')
local rk = CF.ranks({ { owner = 1 }, { owner = 2 }, { owner = 1 }, { owner = 1 } })
eq(rk[4], 0, 'newest of a walker is rank 0') eq(rk[3], 1, 'then 1') eq(rk[1], 2, 'then 2') eq(rk[2], 0, 'another walker has its own ranks')

-- opacity: the newest is strongest, rank and age both fade; gone at the end of its life
local feet = CF.MODES.feet
near(CF.markOpacity(0, 0, feet), feet.alpha, 'a fresh newest mark')
eq(CF.markOpacity(feet.life, 0, feet), nil, 'gone')
eq(CF.markOpacity(1000, 7, feet) < CF.markOpacity(1000, 0, feet), true, 'the oldest of a full trail is fainter at the same age')
near(CF.markOpacity(0, 7, feet), feet.alpha * 0.5, 'rankFade 0.5 at the end of a full trail')
eq(CF.MODES.soft.alpha, 0.6, 'soft: 60% opacity') eq(CF.MODES.soft.tint ~= nil, true, 'soft darkens bright paint')

-- one step is one set of marks; a walker that was moved leaves nothing behind
local lastS = { ox = 5, oy = 5, nx = 6, ny = 5, z = 7, t = 1000 }
eq(CF.sameStep(lastS, { x = 5, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }, 1100, 300), true, 'the pre-walk and the server event')
eq(CF.sameStep(lastS, { x = 5, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }, 1500, 300), false, 'the same tiles again later is a new step')
eq(CF.sameStep(lastS, { x = 6, y = 5, z = 7 }, { x = 7, y = 5, z = 7 }, 1100, 300), false, 'the next step')
eq(CF.sameStep(nil, { x = 1, y = 1, z = 7 }, { x = 2, y = 1, z = 7 }, 0, 300), false, 'no step before')
eq(CF.stillWalking({ x = 6, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }), true, 'at the goal')
eq(CF.stillWalking({ x = 7, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }), true, 'one tile on: the next step already began')
eq(CF.stillWalking({ x = 2, y = 5, z = 7 }, { x = 6, y = 5, z = 7 }), false, 'rubber band: no half-late mark')
eq(CF.stillWalking({ x = 6, y = 5, z = 8 }, { x = 6, y = 5, z = 7 }), false, 'other floor')
eq(CF.stepTime(nil), 300, 'no step time') eq(CF.stepTime(1), CF.STEP_MIN_MS, 'floor') eq(CF.stepTime(99999), CF.STEP_MAX_MS, 'cap')

-- facing and feet
eq(CF.facing(0, -1), 0, 'north') eq(CF.facing(1, 0), 1, 'east') eq(CF.facing(0, 1), 2, 'south') eq(CF.facing(-1, 0), 3, 'west')
eq(CF.facing(1, -1), 1, 'north-east faces east') eq(CF.facing(-1, 1), 3, 'south-west faces west')
eq(CF.footThing({ type = 2073, mount = 0 }), 2073, 'on foot') eq(CF.footThing({ type = 2073, mount = 368 }), 368, 'on its mount')
eq(CF.footThing(nil), nil, 'no outfit')
local tbl = { [7] = { 1, 2, 3, 4, 5, 6, 7, 8 }, [9] = { -50, 90, 10, 10, 10, 10, 10, 10 } }
local x1, y1 = CF.feetOf(tbl, 7, 0) eq(x1 .. ',' .. y1, '1,2', 'north feet')
x1, y1 = CF.feetOf(tbl, 7, 1) eq(x1 .. ',' .. y1, '3,4', 'east feet')
x1, y1 = CF.feetOf(tbl, 7, 2) eq(x1 .. ',' .. y1, '5,6', 'south feet')
x1, y1 = CF.feetOf(tbl, 7, 3) eq(x1 .. ',' .. y1, '7,8', 'west feet')
x1, y1 = CF.feetOf(tbl, 9, 0) eq(x1 .. ',' .. y1, CF.FEET_MIN .. ',' .. CF.FEET_MAX, 'a measured outlier is held to the tile')
x1, y1 = CF.feetOf(tbl, 8, 2) eq(x1 .. ',' .. y1, CF.FEET_FALLBACK[1] .. ',' .. CF.FEET_FALLBACK[2], 'unknown look: fallback')
x1, y1 = CF.feetOf(nil, nil, 2) eq(x1 .. ',' .. y1, CF.FEET_FALLBACK[1] .. ',' .. CF.FEET_FALLBACK[2], 'no table, no look')

-- the half-step schedule (mode feet: 0.2 and 0.7, 3 px to the side), feet at (12, 18) in the tile
local B = CF.MODES.feet
local mk, par = CF.stepMarks(1, 0, 12, 18, 0, B)   -- east
eq(#mk, 2, 'two marks a step') eq(par, 0, 'two marks: the same foot starts the next step')
near(mk[1].at, 0.2, 'first foot at 0.2') near(mk[2].at, 0.7, 'second at 0.7')
eq(mk[1].side, 0, 'the left foot first') eq(mk[2].side, 1, 'then the right')
near(mk[1].px, 12 + 6.4, 'east: 0.2 of a tile ahead of the feet') near(mk[1].py, 18 - 3, 'the left foot is north of the line when walking east')
near(mk[2].py, 18 + 3, 'the right foot is south of the line')
eq(mk[1].tx, 0, 'the first mark is on the old tile') eq(mk[2].tx, 1, 'the second is on the new tile (12 + 22.4 = 34.4)')
near(mk[2].px, 34.4 - 32, 'its place inside that tile')
mk = CF.stepMarks(0, 1, 12, 18, 0, B)   -- south: the right hand side is west
near(mk[1].px, 12 + 3, 'south: the left foot is east of the line') near(mk[2].px, 12 - 3, 'the right foot is west')
near(mk[1].py, 18 + 6.4, 'south: ahead') eq(mk[2].ty, 1, 'second mark on the tile below (18 + 22.4)')
mk = CF.stepMarks(0, -1, 12, 18, 0, B)   -- north
near(mk[1].py, 18 - 6.4, 'north: ahead is up') near(mk[1].px, 12 - 3, 'north: the left foot is west') eq(mk[1].ty, 0, 'old tile') eq(mk[2].ty, -1, 'the tile above')
mk = CF.stepMarks(-1, 0, 12, 18, 0, B)   -- west
near(mk[1].px, 12 - 6.4, 'west: ahead is left') near(mk[1].py, 18 + 3, 'west: the left foot is south')
eq(mk[2].tx, -1, 'west: the second foot is over the tile to the west')
mk = CF.stepMarks(1, 1, 12, 18, 0, B)   -- south-east: the sides are along (-1, 1) / sqrt 2
near(mk[1].px, 12 + 6.4 + 3 / math.sqrt(2) * 1, 'diagonal: x ahead plus the side', 1e-6)
mk, par = CF.stepMarks(1, 0, 12, 18, 1, B)
eq(mk[1].side, 1, 'a step that starts on the right foot') eq(mk[2].side, 0, 'ends on the left')
local one, par1 = CF.stepMarks(1, 0, 12, 18, 0, CF.MODES.pairs)
eq(#one, 1, 'mode pairs: one picture a step') near(one[1].at, 0.5, 'in the middle of the step') near(one[1].py, 18, 'no side offset')
eq(par1, 1, 'one mark flips the foot')
eq(#CF.stepMarks(0, 0, 12, 18, 0, B), 0, 'no step, no marks')
-- walking east a long way: the marks sit half a tile apart, alternating, on the feet line (continuity over steps)
local xs, par2 = {}, 0
for k = 0, 3 do
  local list
  list, par2 = CF.stepMarks(1, 0, 12, 18, par2, B)
  for _, m in ipairs(list) do xs[#xs + 1] = k * 32 + m.tx * 32 + m.px end
end
for i = 2, #xs do near(xs[i] - xs[i - 1], 16, 'half a tile between marks') end
-- the schedule fits inside the step: a stopped walker leaves nothing late
for _, m in ipairs(CF.stepMarks(1, 0, 12, 18, 0, B)) do eq(m.at > 0 and m.at < 1, true, 'inside the step') end
eq(CF.MODE, 'feet', 'option B is built (the owner chooses from the sheets)')
eq(CF.MODES[CF.MODE] ~= nil, true, 'the mode exists')

-- the feet table (client/tools/sprites/gen_foot_marks.py, live pair): the south entry is the character select's feet
local fm = dofile('client/overlay/modules/game_cosmeticfx/foot_marks.lua')
local an = dofile('client/overlay/modules/client_chaos_charselect/outfit_anchors.lua')
eq(fm.dat, an.dat, 'both tables come from the same pair')
local both, same = 0, 0
for id, row in pairs(fm) do
  if type(id) == 'number' and an[id] then
    both = both + 1
    if row[5] == an[id][1] and row[6] == an[id][2] then same = same + 1 end
  end
end
eq(both > 2000, true, 'the table covers the looks of the pair') eq(same, both, 'south feet = outfit_anchors cx, ground (one rule, two tables)')
eq(#fm[2073], 8, 'eight numbers a look')
-- every class look of the server has its feet
local cl = io.open('server/data/scripts/chaos/class_looks_core.lua', 'r')
local text = cl:read('*a') cl:close()
local nl = 0
for male, female in text:gmatch('male = (%d+), female = (%d+)') do
  nl = nl + 1
  eq(type(fm[tonumber(male)]), 'table', 'feet of class look ' .. male) eq(type(fm[tonumber(female)]), 'table', 'feet of class look ' .. female)
end
eq(nl >= 21, true, 'class looks checked')


-- every footprint and outline the server knows has its picture (server cosmetics_config.lua prints / glows)
local cfg = dofile('server/data/scripts/chaos/cosmetics_config.lua')
local function exists(path)
  local f = io.open(path, 'rb')
  if f then f:close() return true end
  return false
end
for _, art in ipairs(cfg.prints) do
  eq(exists('client/overlay/modules/game_cosmeticfx/images/prints/' .. art .. '.png'), true, 'print picture ' .. art)
  eq(exists('client/overlay/modules/game_cosmeticfx/images/marks/' .. art .. '_l.png'), true, 'left mark picture ' .. art)
  eq(exists('client/overlay/modules/game_cosmeticfx/images/marks/' .. art .. '_r.png'), true, 'right mark picture ' .. art)
end
for _, art in ipairs(cfg.glows) do
  eq(exists('client/overlay/modules/game_cosmeticfx/images/glows/' .. art .. '.png'), true, 'glow picture ' .. art)
end
eq(CF.printPath('ember'), '/modules/game_cosmeticfx/images/prints/ember', 'print path')

-- engine outlines (base patch 0038): every outline the server knows has its colours
for _, art in ipairs(cfg.glows) do
  local a = CF.outlineArgs(art, false)
  eq(type(a), 'table', 'outline colours for ' .. art)
  eq(#a, 6, 'r, g, b, a, width, pulse for ' .. art)
  for i = 1, 4 do eq(a[i] >= 0 and a[i] <= 255 and a[i] == math.floor(a[i]), true, 'channel ' .. i .. ' of ' .. art) end
  eq(a[5] >= 1 and a[5] <= 2, true, 'a 1-2 px line for ' .. art)
  eq(a[6], 0, 'no pulse unless the look says so: ' .. art)
end
local pulsing = CF.outlineArgs('radiant', true)
eq(pulsing[6], CF.PULSE_MS, 'a pulsing look breathes at the glow pace')
eq(CF.outlineArgs('gold', false).top, nil, 'one colour')
-- the two gradients of the store (Ember Gradient, Storm Gradient): red at the feet to gold, deep blue to white
local ember = CF.outlineArgs('ember', false)
eq(type(ember.top), 'table', 'ember is a gradient')
eq(ember[1] > ember[2] and ember.top[2] > ember[2], true, 'ember: red below, gold above')
local storm = CF.outlineArgs('storm', false)
eq(storm[3] > storm[1] and storm.top[1] > 200 and storm.top[2] > 200, true, 'storm: blue below, white above')
eq(CF.outlineArgs('nosuchart', false), nil, 'an unknown art draws nothing')
eq(CF.outlineArgs('../gold', false), nil, 'a path is no art key')
-- the outline is server art keyed: every key of the client table is one the server can send
local known = {}
for _, art in ipairs(cfg.glows) do known[art] = true end
for art in pairs(CF.OUTLINES) do eq(known[art], true, 'the server knows outline ' .. art) end
-- the outline kind of the server config carries pulse exactly where the client pulses
for _, c in ipairs(cfg.cosmetics or {}) do
  if c.kind == 'outline' then eq(type(CF.OUTLINES[c.art]), 'table', 'outline cosmetic ' .. c.key) end
end

-- the feature check: an engine with the outline pass, an old one without, and an object that errors on a lookup
eq(CF.hasEngineOutline({ setOutline = function() end }), true, 'patched engine')
eq(CF.hasEngineOutline({}), false, 'old engine keeps the glow picture')
eq(CF.hasEngineOutline(nil), false, 'no creature')
eq(CF.hasEngineOutline(setmetatable({}, { __index = function() error('no field') end })), false, 'a lookup that errors')

print('cosmeticfxlogic_test: ' .. n .. ' checks OK')
