-- luajit helper_runes_test.lua && lua5.3 helper_runes_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'helper_runes.lua')
local R = ChaosHelperRunes
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- ---------------------------------------------------------------- the list against the server's rune supply
local f = io.open(dir .. '../../../../server/data/lib/chaos_rune_supply.lua', 'r')
if f then
  f:close()
  local supply = dofile(dir .. '../../../../server/data/lib/chaos_rune_supply.lua')
  local byId = {}
  for _, r in ipairs(supply.runes) do byId[r.id] = r end
  for _, r in ipairs(R.LIST) do
    local s = byId[r.server]
    eq(s ~= nil, true, r.name .. ' is a rune the server sells')
    eq(s and s.name, r.name, r.name .. ' has the server name')
    -- the stock runes sit 887 above the server id; the three added runes have their own looks
    if r.server < 20000 then eq(r.id - r.server, R.SERVER_OFFSET, r.name .. ' client id') end
  end
else
  print('helper_runes_test: server file not found, the server check was skipped')
end
local seen = {}
for _, r in ipairs(R.LIST) do
  eq(seen[r.id], nil, r.name .. ' id is unique')
  seen[r.id] = true
  eq(r.kind == 'heal' or r.kind == 'attack', true, r.name .. ' kind')
end
-- fields, walls, bombs, summons and the like are never offered
for _, r in ipairs(R.LIST) do
  local n = r.name:lower()
  for _, bad in ipairs({ 'wall', 'patch', 'seed', 'purge', 'beastbond', 'dispel', 'unmaking', 'mimic', 'gravecall', 'thicket',
    'bastion' }) do
    eq(n:find(bad, 1, true), nil, r.name .. ' is no utility rune')
  end
end
eq(R.isHeal(3152), true, 'Mending is a healing rune')
eq(R.isHeal(3155), false, 'a damage rune is no healing rune')
eq(R.isAttack(3155), true, 'Reaper is an attack rune')
eq(R.isAttack(3172), false, 'a field rune is unknown')
eq(R.isAttack(nil), false, 'nil is no rune')
eq(R.info('3152').name, 'Mending Rune', 'info takes a string id')

-- offered: by kind, the class filter only touches runes with a class list
local all = R.offered('attack')
eq(#all > 5, true, 'attack runes offered')
for _, r in ipairs(all) do eq(r.kind, 'attack', 'only attack runes in the attack list') end
local noPaladin = R.offered('attack', function(r) return r.vocations == nil end)
local hasDawn = false
for _, r in ipairs(noPaladin) do if r.id == 3182 then hasDawn = true end end
eq(hasDawn, false, 'the class filter drops Dawnshard')
eq(#R.offered('heal'), 2, 'two healing runes')

-- ---------------------------------------------------------------- healing runes
local rows = { { id = 3152, percent = 60 }, { id = 3160, percent = 40 } }
eq(R.pickHeal(rows, { healthPct = 80 }), nil, 'healthy: no rune')
eq(R.pickHeal(rows, { healthPct = 50 }), 3152, 'below 60: Mending')
eq(R.pickHeal(rows, { healthPct = 30 }), 3160, 'below 40: the lowest threshold goes first')
eq(R.pickHeal(rows, { healthPct = 30, available = function(id) return id ~= 3160 end }), 3152, 'the next row when one is not at hand')
eq(R.pickHeal(rows, { healthPct = 30, available = function() return false end }), nil, 'no rune at hand: none')
eq(R.pickHeal({ { id = 3155, percent = 90 } }, { healthPct = 10 }), nil, 'a damage rune never heals')
eq(R.pickHeal({ { id = 0, percent = 90 } }, { healthPct = 10 }), nil, 'an empty row')
eq(R.pickHeal(nil, { healthPct = 10 }), nil, 'no rows')
eq(R.healDue(rows, 50), true, 'healDue by the numbers')
eq(R.healDue(rows, 90), false, 'healDue off')

-- ---------------------------------------------------------------- attack runes
local from = { x = 100, y = 100, z = 7 }
local function mon(x, y, hp, z) return { position = { x = x, y = y, z = z or 7 }, health = hp or 100 } end
local target = mon(102, 100, 100)
local near = { target, mon(103, 100), mon(110, 100) } -- the third is far from everything
-- a single-target rune counts the monsters near the player
local single = R.info(3155)
eq(R.hits(single, near, from, target.position), 2, 'a single-target rune counts those within the reach')
-- an area rune counts those round the target
local ball = R.info(3191)
eq(R.hits(ball, near, from, target.position), 2, 'an area rune counts round the target')
eq(R.hits(ball, { target, mon(108, 100) }, from, target.position), 1, 'a far monster is not hit')
eq(R.hits(ball, { target, mon(103, 100, 100, 6) }, from, target.position), 1, 'another floor is not hit')
eq(R.hits(ball, { target, mon(103, 100, 20) }, from, target.position, function(e) return e.health >= 50 end), 1,
  'the health filter drops a monster')

eq(R.healthFits({ hpMin = 0, hpMax = 0 }, 100), true, 'no limit')
eq(R.healthFits({ hpMin = 30, hpMax = 0 }, 20), false, 'below the minimum')
eq(R.healthFits({ hpMin = 30, hpMax = 60 }, 70), false, 'above the maximum')
eq(R.healthFits({ hpMin = 30, hpMax = 60 }, 45), true, 'inside the range')

local ord = R.order({ { id = 3155, priority = 3 }, { id = 3191, priority = 1 }, { id = 0, priority = 0 }, { id = 3152, priority = 0 } })
eq(#ord, 2, 'order drops the empty row and the healing rune')
eq(ord[1].id, 3191, 'order by priority')

local ctx = { target = { position = target.position, health = 100 }, from = from, entries = near,
  inRange = function() return true end, available = function() return true end }
local atk = { { id = 3191, creatures = 2, hpMin = 0, hpMax = 0, priority = 1 }, { id = 3155, creatures = 1, hpMin = 0, hpMax = 0, priority = 2 } }
eq(R.pickAttack(atk, ctx).id, 3191, 'the first row that fits')
atk[1].creatures = 3
eq(R.pickAttack(atk, ctx).id, 3155, 'too few monsters: the next row')
ctx.available = function(id) return id ~= 3155 end
eq(R.pickAttack(atk, ctx), nil, 'the rune is not at hand')
ctx.available = function() return true end
ctx.inRange = function() return false end
eq(R.pickAttack(atk, ctx), nil, 'the target is out of reach or sight')
ctx.inRange = function() return true end
ctx.target = nil
eq(R.pickAttack(atk, ctx), nil, 'no target, no rune')
ctx.target = { position = target.position, health = 10 }
atk[2].hpMin = 50
eq(R.pickAttack({ atk[2] }, ctx), nil, 'the target health is below the row minimum')
atk[2].hpMin, atk[2].hpMax = 0, 20
eq(R.pickAttack({ atk[2] }, ctx), nil, 'no monster in the health range is hit')
near[1].health = 10
eq(R.pickAttack({ atk[2] }, ctx).id, 3155, 'and inside the maximum')
eq(R.pickAttack({ { id = 3152, creatures = 1 } }, ctx), nil, 'a healing rune is never thrown at a target')
eq(R.pickAttack({ { id = 0, creatures = 1 } }, ctx), nil, 'an empty row')

-- every rune name has a pt-BR entry (the picker gives it to tr() at run time)
local lf = io.open(dir .. '../client_chaos_locale/pt_br.lua', 'r')
if lf then
  local text = lf:read('*a')
  lf:close()
  for _, r in ipairs(R.LIST) do
    eq(text:find('["' .. r.name .. '"] =', 1, true) ~= nil, true, r.name .. ' has a pt-BR name')
  end
end

if fails > 0 then os.exit(1) end
print('helper_runes_test: ok')
