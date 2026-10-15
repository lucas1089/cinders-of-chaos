-- luajit descentmath_test.lua && lua5.3 descentmath_test.lua (CI runs every client test from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'descentmath.lua')
local M = DescentMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- clock and countdown
eq(M.clock(75), '1:15', 'clock')
eq(M.clock(2700), '45:00', 'clock 45 minutes')
eq(M.clock(-4), '0:00', 'clock negative')
eq(M.clock(nil), '0:00', 'clock nil')
eq(M.left(100, 10, 25), 85, 'left counts down')
eq(M.left(5, 10, 40), 0, 'left never negative')
eq(M.hours(3 * 3600 + 5 * 60 + 9), '3:05 h', 'hours')
eq(M.number(1234567), '1,234,567', 'thousands')
eq(M.number(999), '999', 'small number')
eq(M.number(-4500), '-4,500', 'negative number')
eq(M.number(nil), '0', 'no number')

-- rooms
eq(M.roomLine({ room = 3, rooms = 10, type = 'elite' }), 'Room 3 / 10 - Elite', 'room line')
eq(M.roomLine(nil), '', 'room line nil')
eq(M.roomName('nope'), 'nope', 'unknown room type keeps its key')
eq(M.roomColor('boss'), '#ff6040', 'boss colour')
eq(M.roomColor('x'), M.COLORS.text, 'unknown colour')
eq(M.progress({ depth = 5, rooms = 10 }), 50, 'progress')
eq(M.progress({ depth = 12, rooms = 10 }), 100, 'progress capped')
eq(M.progress({ depth = 1, rooms = 0 }), 0, 'progress without rooms')

-- the state line
eq(M.stateLine({ state = 'fight', type = 'combat', wave = 2, waves = 3, monsters = 5 }), 'Wave 2 / 3 - 5 monsters left', 'waves')
eq(M.stateLine({ state = 'fight', type = 'combat', wave = 0, waves = 2, monsters = 0 }), 'Wave 1 / 2 - 0 monsters left',
  'before the first wave')
eq(M.stateLine({ state = 'fight', type = 'elite', wave = 1, waves = 1, monsters = 1 }), 'Wave 1 / 1 - 1 monster left', 'one left')
eq(M.stateLine({ state = 'fight', type = 'boss', bossName = 'The Pyre Lich' }), 'The Pyre Lich awaits.', 'boss')
eq(M.stateLine({ state = 'choose' }), 'Room cleared: choose a boon.', 'choose')
eq(M.stateLine({ state = 'rest', type = 'shrine' }), 'Use the altar (health for a boon), then Continue.', 'shrine')
eq(M.stateLine({ state = 'rest', type = 'merchant' }), 'Spend your embers at the stand, then Continue.', 'merchant')
eq(M.stateLine({ state = 'rest', type = 'merchant', ready = true }), 'Waiting for the party...', 'ready')
eq(M.stateLine({ state = 'travel' }), 'The next door opens...', 'travel')
eq(M.embersLine({ embers = 1250, reward = 25 }), 'Embers 1,250   Rewards +25%', 'embers with rewards')
eq(M.embersLine({ embers = 30, reward = 0, ward = 400 }), 'Embers 30   Ward 400', 'embers with a ward')

-- icons and tooltips
eq(M.icon('ember_edge'), '/images/game/buffs/descent_b_ember_edge', 'boon icon')
eq(M.icon('frailty', true), '/images/game/buffs/descent_c_frailty', 'curse icon')
eq(M.icon('../x'), '', 'a bad key has no icon')
eq(M.stacksText(2, 3), 'Stack 2 of 3', 'stacks')
eq(M.stacksText(1, 1), '', 'no stacks')
eq(M.tooltip({ n = 'Ember Edge', d = '+24% damage.', s = 2, m = 3 }), 'Ember Edge II\n+24% damage.', 'tooltip with rank')
eq(M.tooltip({ n = 'Phoenix Ember', d = 'Once.', s = 1, m = 1 }), 'Phoenix Ember\nOnce.', 'tooltip unique boon')
eq(M.tooltip({ n = 'Frailty', d = 'More damage.', r = 25 }, true), 'Frailty (curse)\nMore damage.\nRewards +25%', 'curse tooltip')
eq(M.tooltip(nil), '', 'tooltip nil')

-- cards
eq(M.cardTitle({ n = 'Keen Eye', s = 0, m = 3 }), 'Keen Eye', 'new card title')
eq(M.cardTitle({ n = 'Keen Eye', s = 1, m = 3 }), 'Keen Eye II', 'card title of the next rank')
eq(M.cardTitle({ n = 'Searing Brand', s = 0, m = 1 }), 'Searing Brand', 'unique card title')
eq(M.cardNote({ s = 0, m = 3 }), 'New (stacks to 3)', 'note new')
eq(M.cardNote({ s = 2, m = 3 }), 'Held 2 of 3', 'note held')
eq(M.cardNote({ s = 0, m = 1 }), 'Unique boon', 'note unique')
local xs = M.cardLayout(3, 180, 14, 600)
eq(#xs, 3, 'three cards')
eq(xs[1], 16, 'first card centred')
eq(xs[2] - xs[1], 194, 'card step')
eq(xs[3] + 180 + xs[1], 600, 'symmetric')
eq(#M.cardLayout(0, 180, 14, 600), 0, 'no cards')
eq(M.cardLayout(1, 180, 14, 600)[1], 210, 'one card in the middle')
eq(M.curseLine({ n = 'Frailty', d = 'You take 20% more damage.', r = 25, e = 30 }),
  'Frailty - You take 20% more damage. (+25% rewards, +30 embers)', 'curse line')
eq(M.curseLine({ n = 'Ashen Purse', d = 'Fewer embers.', r = 15, e = 0 }), 'Ashen Purse - Fewer embers. (+15% rewards)', 'curse without embers')

-- merchant
local w = M.ware({ p = 44 }, 50)
eq(w.can, true, 'affordable')
eq(w.text, '44 embers', 'price text')
eq(M.ware({ p = 44 }, 43).can, false, 'too dear')
eq(M.ware({ p = 10, off = true }, 99).can, false, 'not needed')
eq(M.ware(nil, 5).can, false, 'no ware')

-- the entry window
local info = { rooms = { 8, 12 }, timeLimit = 2700, maxPlayers = 4, minLevel = 100, level = 250, freeDaily = true,
  freeWeekly = false, nextDaily = 0, sigils = 2, craft = { name = 'Ember Sigil', shards = 25, gold = 50000, haveShards = 30,
  haveGold = 49999 }, best = 7, bestClear = false, runs = 4, clears = 0, weekSeed = 123, weekBest = 6 }
local lines = M.infoLines(info)
eq(lines[1].text, '8-12 rooms, 45 minutes, up to 4 players. Level 100+.', 'rules line')
eq(lines[2].text, 'Free descent today: ready', 'daily ready')
eq(lines[3].text, 'Free weekly descent: used this week', 'weekly used')
eq(lines[4].text, 'Ember Sigil: 2 carried', 'sigils')
eq(lines[5].text, 'Best depth: 7   Runs: 4   Clears: 0', 'records')
eq(lines[6].text, 'This week (seed 123): best depth 6', 'weekly record')
info.freeDailyCount = 3
eq(M.infoLines(info)[2].text, 'Free descents: 3 ready (unused days bank up to 3)', 'banked free runs')
info.freeDailyCount = 1
eq(M.infoLines(info)[2].text, 'Free descent today: ready', 'one free run: the old line')
info.freeDailyCount = nil
info.freeDaily, info.nextDaily = false, 3 * 3600 + 600
eq(M.infoLines(info)[2].text, 'Free descent today: used (next in 3:10 h)', 'daily used')
local c = M.craft(info)
eq(c.can, false, 'one gold short')
eq(c.text, 'Forge: 25 rune shards (30) and 50,000 gold (49,999)', 'craft line')
info.craft.haveGold = 50000
eq(M.craft(info).can, true, 'enough to forge')
local b = M.entryButtons(info)
eq(b.normal.can, true, 'a sigil pays the normal run')
eq(b.normal.text, 'Descend (1 sigil)', 'normal with a sigil')
eq(b.weekly.text, 'Weekly Descent (1 sigil)', 'weekly with a sigil')
info.sigils = 0
eq(M.entryButtons(info).normal.can, false, 'nothing to pay with')
info.freeWeekly = true
eq(M.entryButtons(info).weekly.text, 'Weekly Descent (free)', 'free weekly')
info.level = 50
eq(M.entryButtons(info).weekly.can, false, 'too low')
info.level, info.inRun = 250, true
eq(M.entryButtons(info).weekly.can, false, 'already inside')
eq(M.entryButtons(nil).normal.can, false, 'no info')

-- the end
local e = M.endLines({ result = 'cleared', depth = 10, rooms = 10, gold = 250000, weekly = true,
  items = { { name = 'Orbs of Fate', count = 3 }, { name = 'Pyre Cleaver', count = 1, unique = true } }, title = 'Heart of the Descent' })
eq(e.title, 'The Descent is conquered!', 'end title')
eq(e.lines[1], 'Depth 10 of 10 (weekly)', 'end depth')
eq(e.lines[2], '250,000 gold to your bank', 'end gold')
eq(e.lines[3], '3 Orbs of Fate', 'end orbs')
eq(e.lines[4], 'Unique: Pyre Cleaver', 'end unique')
eq(e.lines[5], 'New title: Heart of the Descent', 'end title line')
eq(M.endLines({ result = 'fallen', depth = 2, rooms = 9 }).color, '#ff6040', 'fallen colour')
eq(#M.endLines({ result = 'time', depth = 0, rooms = 9 }).lines, 1, 'nothing earned')
eq(M.partyLine({ name = 'Ana', alive = true, hp = 80 }), 'Ana 80%', 'party member')
eq(M.partyLine({ name = 'Bo', alive = false }), 'Bo (out)', 'party member out')

if fails > 0 then
  print(string.format('descent client tests: %d of %d FAILED', fails, checks))
  os.exit(1)
end
print(string.format('descent client tests OK (%d checks)', checks))
