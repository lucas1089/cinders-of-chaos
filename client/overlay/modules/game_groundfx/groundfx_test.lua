-- luajit groundfx_test.lua && lua5.3 groundfx_test.lua (from the repo root: path client/overlay/modules/game_groundfx/)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'groundfx_data.lua')
dofile(dir .. 'groundfx.lua')
local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then print('FAIL ' .. what); fails = fails + 1 end
end

-- the data: sorted, unique ids, every id named
local ids, names = GroundFxData.ids, GroundFxData.names
ok(#ids > 100, 'many ground effects: ' .. #ids)
local seen, count = {}, 0
for i, id in ipairs(ids) do
  ok(type(id) == 'number' and id >= 1 and id <= 65535, 'id in range ' .. tostring(id))
  ok(not seen[id], 'id once ' .. id)
  seen[id] = true
  if i > 1 then ok(ids[i - 1] < id, 'sorted at ' .. i) end
  ok(type(names[id]) == 'string', 'named ' .. id)
end
for id in pairs(names) do count = count + 1; ok(seen[id], 'name has an id ' .. id) end
ok(count == #ids, 'names and ids match')

-- shapes the owner saw over the creatures are in the list (by name, so a new pair cannot move them silently)
local byName = {}
for id, n in pairs(names) do byName[n] = id end
for _, n in ipairs({'portal_pad', 'big_nova_void_7', 'big_rift_void_7', 'nova_frost', 'meteor_fall', 'void_maw',
                    'arcane_sigil', 'frost_glyph', 'infernal_seal', 'boss_telegraph', 'fx:arcane_circle'}) do
  ok(byName[n] ~= nil, n .. ' is a ground effect')
end
-- short hits and the status words stay above the creatures
for _, n in ipairs({'arcane_hit', 'lightning_hit', 'word_blessed', 'fx:CONST_ME_ENERGYHIT', 'illusion_shatter'}) do
  ok(byName[n] == nil, n .. ' is not a ground effect')
end
ok(GroundFx.isGround(byName.portal_pad), 'isGround')
ok(not GroundFx.isGround(1), 'blood hit is not ground')

-- apply: every id set on, then off; no API -> false, nothing thrown
local set = {}
local map = {setGroundEffect = function(id, on) set[id] = on end}
ok(GroundFx.apply(map, ids, true) == true, 'apply on')
local all = true
for _, id in ipairs(ids) do all = all and set[id] == true end
ok(all, 'every id on')
GroundFx.apply(map, ids, false)
all = true
for _, id in ipairs(ids) do all = all and set[id] == false end
ok(all, 'every id off')
ok(GroundFx.apply({}, ids, true) == false, 'no API')
ok(GroundFx.apply(nil, ids, true) == false, 'no map')
local bad = {setGroundEffect = function() error('boom') end}
ok(GroundFx.apply(bad, ids, true) == true, 'a failing call is caught')

print(string.format('groundfx: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
