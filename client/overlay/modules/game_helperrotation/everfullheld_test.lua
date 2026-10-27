-- luajit everfullheld_test.lua && lua5.3 everfullheld_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'everfullheld.lua')
local E = ChaosEverfullHeld
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(E.OPCODE, 116, 'opcode')
eq(next(E.get()), nil, 'nothing held before the first message')

eq(E.apply({ v = 1, health = { look = 239, tier = 2, level = 80, line = 'health', ready = true },
  mana = { look = 23373, tier = 3, level = 130, line = 'mana', ready = false } }), true, 'a message')
local v = E.get()
eq(v.health.look, 239, 'health look') eq(v.health.tier, 2, 'tier') eq(v.health.level, 80, 'level') eq(v.health.ready, true, 'ready')
eq(v.mana.look, 23373, 'mana look') eq(v.mana.ready, false, 'mana not ready')
v.health.look = 1
eq(E.get().health.look, 239, 'a caller cannot change the held view')

-- the next message replaces the view: a slot that is absent is no longer carried
E.apply({ v = 1, health = { look = 7642, tier = 2, level = 80, line = 'spirit', ready = true } })
eq(E.get().health.line, 'spirit', 'spirit in the health slot') eq(E.get().mana, nil, 'the mana slot is gone')
E.apply({ v = 1 })
eq(next(E.get()), nil, 'an empty message: nothing carried')

-- a message that does not fit is dropped slot by slot
E.apply({ health = { look = 'x', tier = 2, level = 80, line = 'health', ready = true },
  mana = { look = 238, tier = 2, level = 80, line = 'mana', ready = true } })
eq(E.get().health, nil, 'a look that is no number') eq(E.get().mana.look, 238, 'the good slot stays')
E.apply({ health = { look = 239.5, tier = 2, level = 80, line = 'health' } }) eq(E.get().health, nil, 'a fraction')
E.apply({ health = { look = 0, tier = 2, level = 80, line = 'health' } }) eq(E.get().health, nil, 'look 0')
E.apply({ health = { look = 70000, tier = 2, level = 80, line = 'health' } }) eq(E.get().health, nil, 'a look over 65535')
E.apply({ health = { look = 239, tier = 0, level = 80, line = 'health' } }) eq(E.get().health, nil, 'tier 0')
E.apply({ health = { look = 239, tier = 2, level = -1, line = 'health' } }) eq(E.get().health, nil, 'negative level')
E.apply({ health = { look = 239, tier = 2, level = 80, line = 'potion' } }) eq(E.get().health, nil, 'an unknown line')
E.apply({ health = { look = 239, tier = 2, level = 80, line = 'mana' } }) eq(E.get().health, nil, 'a mana flask in the health slot')
E.apply({ mana = { look = 238, tier = 2, level = 80, line = 'health' } }) eq(E.get().mana, nil, 'a health flask in the mana slot')
E.apply({ mana = { look = 238, tier = 2, level = 80, line = 'spirit' } }) eq(E.get().mana, nil, 'a spirit flask in the mana slot')
E.apply({ health = { look = 239, tier = 2, level = 80, line = 'health', ready = 'yes' } })
eq(E.get().health.ready, false, 'ready only when true')
eq(E.apply('x'), false, 'not a table') eq(E.apply(nil), false, 'nil')
E.apply({ health = 5, mana = 'a' }) eq(next(E.get()), nil, 'slots that are no tables')
E.reset() eq(next(E.get()), nil, 'reset')

E.reset() eq(E.received(), false, 'nothing received after reset')
E.apply({}) eq(E.received(), true, 'a message arrived')
E.reset()

if fails > 0 then os.exit(1) end
print('everfullheld_test: ok')
