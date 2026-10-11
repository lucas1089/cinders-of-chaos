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
local size, ml, mt = CF.printBox(64, 64, 32)
eq(size, 58, 'print size') eq(ml, 0, 'centred at 64 px tiles') eq(mt, 0, 'centred')
size, ml, mt = CF.printBox(96, 96, 32)
eq(ml, 16, 'shifted on bigger tiles') eq(mt, 16, 'shifted')
eq(CF.glowSize(32), 64, 'glow covers two tiles')

-- every footprint and outline the server knows has its picture (server cosmetics_config.lua prints / glows)
local cfg = dofile('server/data/scripts/chaos/cosmetics_config.lua')
local function exists(path)
  local f = io.open(path, 'rb')
  if f then f:close() return true end
  return false
end
for _, art in ipairs(cfg.prints) do
  eq(exists('client/overlay/modules/game_cosmeticfx/images/prints/' .. art .. '.png'), true, 'print picture ' .. art)
end
for _, art in ipairs(cfg.glows) do
  eq(exists('client/overlay/modules/game_cosmeticfx/images/glows/' .. art .. '.png'), true, 'glow picture ' .. art)
end
eq(CF.printPath('ember'), '/modules/game_cosmeticfx/images/prints/ember', 'print path')

print('cosmeticfxlogic_test: ' .. n .. ' checks OK')
