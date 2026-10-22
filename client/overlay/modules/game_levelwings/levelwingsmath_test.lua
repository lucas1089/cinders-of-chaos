-- luajit levelwingsmath_test.lua && lua5.3 levelwingsmath_test.lua (from any folder)
-- The level-up effect: its id and offset are those of w_fx_level_up in the server ids file (pair 36), the tile it goes
-- to, the settings rule and the server message check.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'levelwingsmath.lua')
local M = LevelWingsMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the effect of the pair
local f = io.open(dir .. '../../../../server/data/lib/chaos_pack36_fx_ids.lua', 'r')
local text = f and f:read('*a') or ''
if f then f:close() end
local id, dx, dy = text:match('\nChaosVfx%.' .. M.EFFECT_NAME .. ' = {id = (%d+), dx = (%d+), dy = (%d+)')
eq(M.EFFECT.id, tonumber(id), 'the id of ' .. M.EFFECT_NAME)
eq(M.EFFECT.dx, tonumber(dx), 'its x offset')
eq(M.EFFECT.dy, tonumber(dy), 'its y offset')
eq(M.EFFECT.id > 854, true, 'an effect appended in pair 36')

-- the tile
local p = M.effectPos({ x = 100, y = 200, z = 7 })
eq(p.x, 100 + M.EFFECT.dx, 'x moved by the offset')
eq(p.y, 200 + M.EFFECT.dy, 'y moved by the offset')
eq(p.z, 7, 'same floor')
eq(M.effectPos(nil), nil, 'no position')
eq(M.effectPos({ x = 1 }), nil, 'half a position')

-- settings
eq(M.wanted(true, true, false), true, 'own on, others off: own plays')
eq(M.wanted(false, true, false), false, 'others off')
eq(M.wanted(true, false, true), false, 'own off')
eq(M.wanted(false, false, true), true, 'others on')
eq(M.wanted(true, nil, nil), true, 'no settings: on')
eq(M.wanted(false, nil, nil), true, 'no settings: on for others')

-- the message
eq(M.playId({ action = 'play', data = { id = 268435457, lv = 44, n = 3 } }), 268435457, 'play id')
eq(M.playId({ action = 'play', data = { id = '12' } }), 12, 'id as text')
eq(M.playId({ action = 'other', data = { id = 5 } }), nil, 'other action')
eq(M.playId({ action = 'play' }), nil, 'no data')
eq(M.playId({ action = 'play', data = { id = 0 } }), nil, 'id 0')
eq(M.playId({ action = 'play', data = { id = 1.5 } }), nil, 'fraction')
eq(M.playId('play'), nil, 'not a table')

print(string.format('levelwingsmath: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
