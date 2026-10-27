-- luajit pvpzoneview_test.lua && lua5.3 pvpzoneview_test.lua (CI runs it from the repository root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'pvpzoneview.lua')
local V = PvpZoneView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(V.clock(125), '2:05', 'clock'); eq(V.clock(3725), '1:02:05', 'clock hours'); eq(V.clock(-3), '0:00', 'never negative')
eq(V.number(1234567), '1,234,567', 'number'); eq(V.number(nil), '0', 'nil number'); eq(V.number(999), '999', 'small')
eq(V.span(42), '42s', 'span s'); eq(V.span(600), '10m', 'span m'); eq(V.span(3900), '1h 5m', 'span h'); eq(V.span(7200), '2h', 'span 2h')

-- HUD
eq(V.embersLine({ embers = 1250, cap = 2500 }), 'Embers 1,250 / 2,500', 'embers line')
local p, col = V.carryPercent({ embers = 1250, cap = 2500 })
eq(p, 50, 'carry percent'); eq(col, '#e8a040', 'carry colour')
p, col = V.carryPercent({ embers = 2400, cap = 2500 })
eq(col, '#ff5a2a', 'nearly full colour')
eq((V.carryPercent({ embers = 5, cap = 0 })), 0, 'no cap')
eq((V.contestLine({ phase = 'idle', left = 3600 })), 'Shrine contest in 1:00:00', 'idle')
eq((V.contestLine({ phase = 'warden', left = 600, warden = 73 })), 'Shrine Warden 73% - 10:00 left', 'warden')
eq((V.contestLine({ phase = 'capture', left = 90, contested = true })), 'Shrine: CONTESTED - 1:30 left', 'contested')
local line, c2 = V.contestLine({ phase = 'capture', left = 90, progress = { { short = 'Vigil', pct = 42, color = '#e0a050' } } })
eq(line, 'Shrine: Vigil 42% - 1:30 left', 'capture lead'); eq(c2, '#e0a050', 'lead colour')
eq((V.contestLine({ phase = 'capture', left = 5, progress = {} })), 'Shrine: open, take it! - 0:05 left', 'open')
eq((V.contestLine(nil)), 'Shrine contest in 0:00', 'nil contest')
eq((V.holderLine({ holder = { short = 'Choir', left = 3000, color = '#b07ae8' } })), 'Choir hold the shrine (50m)', 'holder')
eq((V.holderLine({})), 'Nobody holds the Cinder Shrine', 'no holder')
eq((V.pledgeLine({ name = 'The Ashen Vigil' })), 'Fighting for The Ashen Vigil', 'pledge')
eq((V.pledgeLine(nil)), 'Not pledged: no reputation, no shrine', 'no pledge')
eq((V.statusLine({ exit = 40, protect = 5 })), 'Leaving... 40% (do not fight)', 'exit first')
eq((V.statusLine({ protect = 7 })), 'Protected for 7s', 'protected')
eq((V.statusLine({ piles = 1500 })), '1,500 embers lie on the ground', 'piles')
eq((V.statusLine({})), 'Bank your embers at a safe exit', 'default status')

-- the window and the confirmation
local t, en = V.enterButton({ canEnter = true })
eq(t, 'Enter the Marches', 'enter text'); eq(en, true, 'enter enabled')
local _, en2, tip = V.enterButton({ canEnter = false, why = 'You need level 150.' })
eq(en2, false, 'refused'); eq(tip, 'You need level 150.', 'reason as tooltip')
eq(select(2, V.enterButton({ inside = true, canEnter = true })), false, 'inside: no enter')
eq(V.canConfirm({}, false), false, 'must tick the box')
eq(V.canConfirm({}, true), true, 'ticked')
eq(V.canConfirm({ hc = { isHc = true, allow = false } }, true, true), false, 'Hardcore never (decided)')
eq(V.canConfirm({ hc = { isHc = true, allow = true } }, true, false), false, 'Hardcore allowed: second box needed')
eq(V.canConfirm({ hc = { isHc = true, allow = true } }, true, true), true, 'Hardcore allowed: both boxes')
local risk = V.riskText({ rules = { 'Open PvP.', 'Embers drop.' }, carried = 1200, pickup = { perKill = 800 } })
eq(risk, '- Open PvP.\n- Embers drop.\nYou carry 1,200 embers now. A defeat drops them all; your killer may take up to 800 of them.',
  'risk text')
eq(V.riskText({ hc = { isHc = true, allow = false } }):find('cannot enter', 1, true) ~= nil, true, 'Hardcore risk line')
local name, b, ok, tt = V.factionRow({ name = 'The Veiled Choir', rival = 'vigil', rivalName = 'The Ashen Vigil', can = true }, {})
eq(name, 'The Veiled Choir', 'faction'); eq(b, 'Pledge', 'pledge button'); eq(ok, true, 'can pledge'); eq(tt, 'sworn rival: The Ashen Vigil', 'rival tip')
_, b, ok, tt = V.factionRow({ name = 'X', pledged = true }, { pledgeChangeIn = 7200 })
eq(b, 'Pledged', 'pledged'); eq(ok, false, 'pledged disabled'); eq(tt, 'You can change in 2h', 'change wait')
_, _, ok, tt = V.factionRow({ name = 'Y', can = false, why = 'Not trusted.' }, {})
eq(ok, false, 'cannot pledge'); eq(tt, 'Not trusted.', 'why')
local sub, btn, can = V.vendorRow({ cost = 300, weekly = 5, bought = 2, can = true }, 400)
eq(sub, '2 of 5 this week', 'weekly sub'); eq(btn, '300 embers', 'price'); eq(can, true, 'can buy')
_, _, can = V.vendorRow({ cost = 300, can = true }, 100)
eq(can, false, 'too poor')
_, btn, can = V.vendorRow({ cost = 4000, kind = 'cosmetic', owned = true }, 9999)
eq(btn, 'Owned', 'owned'); eq(can, false, 'owned disabled')
eq(V.recordLine({ banked = 1500, weekBanked = 300, total = 9000, kills = 3, defeats = 1, captures = 2 }),
  'Banked 1,500 (this week 300, all time 9,000)   Defeats dealt 3, taken 1   Shrines 2', 'record line')

-- how it works: four numbered steps
local steps = V.steps({ carryMax = 2500, pickup = { perKill = 800 }, exitSeconds = 5 })
eq(#steps, 4, 'four steps')
for i, line in ipairs(steps) do eq(line:sub(1, 3), i .. '. ', 'step ' .. i .. ' numbered') end
eq(steps[2]:find('2,500', 1, true) ~= nil, true, 'step 2 names the carry cap')
eq(steps[3]:find('800', 1, true) ~= nil, true, 'step 3 names what a killer takes')
eq(steps[4]:find('5s', 1, true) ~= nil, true, 'step 4 names the exit time')
eq(#V.steps(nil), 4, 'steps without a state')

-- map marks from the server
local clean = V.cleanMarks({ { kind = 'exit', x = 13319, y = 13362, z = 7, name = 'Safe exit' }, { kind = 'shrine', x = 13348, y = 13340, z = 7 },
  { kind = 'door', x = 1, y = 1, z = 7 }, { kind = 'exit', x = 'a', y = 1, z = 7 }, 'x' })
eq(#clean, 2, 'only exits and the shrine with numbers')
eq(clean[2].name, '', 'a missing name is empty')
eq(#V.cleanMarks('nope'), 0, 'not a list')
local many = {}
for i = 1, 20 do many[i] = { kind = 'exit', x = i, y = i, z = 7 } end
eq(#V.cleanMarks(many), 8, 'at most 8 marks')

-- the compass and the nearest mark
local d, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 100, y = 80, z = 7 })
eq(d, 20, 'distance north'); eq(dir, 'n', 'north')
d, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 130, y = 70, z = 7 })
eq(d, 30, 'distance north-east'); eq(dir, 'ne', 'north-east')
_, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 140, y = 105, z = 7 }); eq(dir, 'e', 'east (flat angle)')
_, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 90, y = 130, z = 7 }); eq(dir, 's', 'south (steep angle)')
_, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 70, y = 120, z = 7 }); eq(dir, 'sw', 'south-west')
_, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 70, y = 100, z = 7 }); eq(dir, 'w', 'west')
_, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 80, y = 80, z = 7 }); eq(dir, 'nw', 'north-west')
_, dir = V.compass({ x = 100, y = 100, z = 7 }, { x = 110, y = 110, z = 7 }); eq(dir, 'se', 'south-east')
d, dir = V.compass({ x = 5, y = 5, z = 7 }, { x = 5, y = 5, z = 7 }); eq(d, 0, 'on the spot'); eq(dir, nil, 'no direction')
eq(V.whereText(23, 'ne'), '23 tiles north-east', 'where text'); eq(V.whereText(0, nil), 'you are here', 'where, on it')
local mk = { { kind = 'exit', x = 100, y = 140, z = 7 }, { kind = 'exit', x = 160, y = 100, z = 7 }, { kind = 'shrine', x = 130, y = 120, z = 7 },
  { kind = 'exit', x = 101, y = 101, z = 8 } }
local m, where = V.nearest(mk, 'exit', { x = 110, y = 130, z = 7 })
eq(m.x, 100, 'nearest exit'); eq(where, '10 tiles south-west', 'nearest exit text')
_, where = V.nearest(mk, 'shrine', { x = 130, y = 100, z = 7 }); eq(where, '20 tiles south', 'shrine text')
eq(V.nearest(mk, 'shrine', { x = 130, y = 100, z = 9 }), nil, 'another floor: no mark')
eq(V.nearest(nil, 'exit', { x = 1, y = 1, z = 7 }), nil, 'no marks')

-- the objective line
local g = V.goalLines({ embers = 12 }, '23 tiles north', nil)
eq(#g, 1, 'one line without an event')
eq(g[1][1], 'Embers carried: 12. Bank them at the nearest safe exit (23 tiles north, marked on your map) before you are defeated.', 'carrying: bank them')
g = V.goalLines({ embers = 1500 }, nil, nil)
eq(g[1][1], 'Embers carried: 1,500. Bank them at a safe exit (marked on your map) before you are defeated.', 'carrying, no mark known')
g = V.goalLines({ embers = 0 }, '5 tiles east', nil)
eq(g[1][1], 'Goal: kill monsters and rival players for embers, then bank them at a safe exit (marked on your map).', 'empty hands: the goal')
g = V.goalLines({ embers = 30, exit = 40 }, '5 tiles east', nil)
eq(#g, 1, 'leaving: one line'); eq(g[1][1]:find('hold still', 1, true) ~= nil, true, 'leaving: hold still')
g = V.goalLines({ embers = 30, contest = { phase = 'warden' } }, '5 tiles east', '12 tiles west')
eq(#g, 2, 'a shrine line during the warden')
eq(g[2][1], 'Shrine event: slay the Shrine Warden at the shrine (12 tiles west, marked on your map).', 'warden line')
g = V.goalLines({ embers = 0, contest = { phase = 'capture' }, pledge = { key = 'vigil' } }, nil, '3 tiles north')
eq(g[2][1], 'Shrine event: stand in the shrine circle with your faction to take it (3 tiles north, marked on your map).', 'capture line')
g = V.goalLines({ embers = 0, contest = { phase = 'capture' } }, nil, nil)
eq(g[2][1], 'Shrine event: only players pledged to a faction can take the shrine.', 'capture, unpledged')
eq(#V.goalLines(nil, nil, nil), 1, 'no data: the goal')

print(string.format('pvpzoneview_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
