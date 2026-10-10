-- luajit raidview_test.lua && lua5.3 raidview_test.lua (CI runs it from the repository root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'raidview.lua')
local V = RaidView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- clocks and numbers
eq(V.clock(0), '0:00', 'clock 0'); eq(V.clock(125), '2:05', 'clock'); eq(V.clock(-3), '0:00', 'clock never negative')
eq(V.left(60, 100, 110), 50, 'left'); eq(V.left(5, 0, 99), 0, 'left floor')
eq(V.resetText(2 * 86400 + 5 * 3600 + 40), '2d 5h', 'reset days'); eq(V.resetText(3 * 3600 + 12 * 60), '3h 12m', 'reset hours')
eq(V.resetText(59), '0m', 'reset minutes')
eq(V.number(2500000), '2,500,000', 'number'); eq(V.number(999), '999', 'small number'); eq(V.number(nil), '0', 'nil number')

-- the lockouts
local info = { name = 'The Ashen Sepulchre', minLevel = 800, level = 900, minPlayers = 5, maxPlayers = 15,
  lock = { bosses = { { k = 'ulthar', n = 'Gravewarden Ulthar', l = true }, { k = 'morwen', n = 'Morwen the Ash-Sister' } },
    looted = 1, total = 2, reset = 90000 },
  saved = { { id = 12, killed = { true, false }, done = 1, next = 'Morwen the Ash-Sister', leader = 'Ash', members = 6 },
    { id = 11, killed = { true, true }, done = 2, leader = 'Bo', cleared = true },
    { id = 13, killed = { false, false }, done = 0, next = 'Gravewarden Ulthar', leader = 'Cy', open = true },
    { id = 14, killed = { false, false }, done = 0, next = 'Gravewarden Ulthar', leader = 'Di', open = true, inside = true } },
  marks = 1234, kills = 7, clears = 1, best = 1500, vendor = { marks = 130, stock = {} } }
local rows = V.lockRows(info)
eq(#rows, 2, 'a row per boss'); eq(rows[1].looted, true, 'looted'); eq(rows[1].state, 'Looted this week', 'looted text')
eq(rows[2].looted, false, 'free'); eq(rows[2].text, '2. Morwen the Ash-Sister', 'numbered')
eq(V.lockSummary(info), '1 of 2 bosses looted this week. Lockouts reset in 1d 1h.', 'summary')
eq(#V.lockRows({}), 0, 'no lock data')

-- saved raids: continue, cleared, join, inside
local r = V.savedRow(info.saved[1])
eq(r.title, 'Raid #12 (Ash)', 'title'); eq(r.progress, '1 / 2 slain  [X-]', 'progress'); eq(r.action, 'continue', 'continue')
eq(r.next, 'Next: Morwen the Ash-Sister', 'next boss')
r = V.savedRow(info.saved[2])
eq(r.action, nil, 'a cleared raid has no button'); eq(r.next, 'Cleared', 'cleared')
eq(V.savedRow(info.saved[3]).action, 'join', 'an open raid is joined'); eq(V.savedRow(info.saved[4]).action, 'inside', 'inside')
eq(V.actionText('join'), 'Join', 'button text'); eq(V.actionText(nil), '', 'no button')

-- the start button
eq(V.startState(info).can, true, 'can open')
eq(V.startState({ minLevel = 800, level = 700 }).can, false, 'level')
eq(V.startState({ inRaid = true, minLevel = 1, level = 2 }).text, 'In a raid', 'inside')
eq(V.recordLine(info), 'Sepulchre Marks: 1,234   Bosses looted: 7   Full clears: 1   Best clear: 25:00', 'record')

-- the journal
local j = V.journalBoss({ n = 'Varkhul the Ashen Sovereign', final = true, intro = 'i', roles = 'r', enrage = 780,
  phases = { { n = 'The Throne', at = 100 }, { n = 'Court of Ash', at = 70 } }, mech = { 'one', 'two' },
  loot = { gold = 6000000, marks = 45, items = { { id = 29856, count = 12, n = 'orbs of upheaval' }, { id = 29855, count = 1 } },
    gear = { 1, 2, 3 }, gearRolls = 3, gearLevel = { 120, 130 }, unique = 400, uniques = { 'A', 'B' } } }, 5)
eq(j.title, '5. Varkhul the Ashen Sovereign (final)', 'journal title')
eq(j.phases, 'Phases: The Throne (100%), Court of Ash (70%). Enrage at 13:00.', 'phases')
eq(#j.mech, 2, 'mechanics'); eq(j.mech[1], '- one', 'mechanic line')
eq(j.loot[1], '6,000,000 gold to the bank, 45 Sepulchre Marks', 'gold and marks')
eq(j.loot[2], '12 orbs of upheaval', 'item with a name'); eq(j.loot[3], '1 Exalted Orb', 'item by id')
eq(j.loot[4], '3 gear rolls, item level 120-130 (3 base items)', 'gear')
eq(j.loot[5], '4.0% chance of a raid unique: A, B', 'uniques')
eq(V.journalBoss(nil, 1).title, '1. ?', 'empty boss')

-- the vendor
local v = V.vendorRow({ k = 'v_helm', n = 'Sepulchre Warden Helm', kind = 'gear', price = 120, weekly = 1, bought = 0,
  level = 130, rarity = 4, mods = { 'a +1 (T7)', 'b (T7)' } }, 130)
eq(v.sub, 'Epic, item level 130: a +1 (T7), b (T7)', 'gear line'); eq(v.button, '120 marks', 'price'); eq(v.can, true, 'can buy')
eq(V.vendorRow({ kind = 'gear', price = 120, weekly = 1, bought = 0 }, 100).can, false, 'too few marks')
local o = V.vendorRow({ n = 'Ashen Upheaval (10)', kind = 'orbs', price = 40, weekly = 3, bought = 3,
  items = { { n = 'orbs of upheaval', c = 10 } } }, 999)
eq(o.sub, '10 orbs of upheaval', 'orb line'); eq(o.button, 'Sold out', 'weekly limit'); eq(o.can, false, 'sold out')
eq(o.limit, '3 / 3 this week', 'limit')

-- the HUD
local d = { raid = 'The Ashen Sepulchre', id = 12, boss = 'Morwen the Ash-Sister', idx = 2, total = 5, done = 1,
  state = 'fight', hp = 64, phase = 2, phases = 2, phaseName = 'Requiem', enrage = 30, players = 12, fallen = 2, adds = 3,
  stacks = { sunder = 3, hexed = 0 }, hexed = 5, alerts = { 'x' } }
eq(V.hudTitle(d), 'The Ashen Sepulchre #12', 'hud title'); eq(V.progress(d), 20, 'progress')
eq(V.bossLine(d), '2. Morwen the Ash-Sister - 64%', 'fight line'); eq(V.phaseLine(d), 'Phase 2 of 2: Requiem', 'phase line')
local t, c = V.enrageText(d, 30)
eq(t, 'Enrage 0:30', 'enrage clock'); eq(c, '#ff9a30', 'enrage soon')
d.enraged = true
eq((V.enrageText(d, 0)), 'ENRAGED', 'enraged')
eq(V.countsLine(d), 'Raiders 12, fallen 2, adds 3', 'counts')
eq(V.stacksLine(d), 'Sundered x3   WITHERING HEX 5s: cleanse!', 'own marks')
eq(V.bossLine({ state = 'idle', idx = 3, boss = 'The Marrow Colossus', trash = 4 }), '3. The Marrow Colossus - clear the corridor (4 left)', 'trash')
eq(V.bossLine({ state = 'idle', idx = 3, boss = 'The Marrow Colossus' }), '3. The Marrow Colossus awaits', 'idle')
eq(V.bossLine({ state = 'clear' }), 'Every boss is slain.', 'clear')
eq(V.phaseLine({ state = 'idle' }), '', 'no phase out of a fight')
eq((V.enrageText({ state = 'idle' }, 0)), '', 'no clock out of a fight')
eq(V.progress({ total = 0 }), 0, 'progress without bosses')

-- call-outs and loot
eq(V.alertColor('fail'), '#ff4030', 'fail colour'); eq(V.alertColor('nope'), '#f6cf72', 'default colour')
eq(V.alertSeconds('kill'), 6, 'kill stays longer'); eq(V.alertSeconds('mech'), 4, 'mechanics')
eq(V.lootSummary({ boss = 'B', eligible = true, lines = { 'x', 'y' } }), 'Spoils of B: x, y', 'loot')
eq(V.lootSummary({ boss = 'B' }), 'B slain. You looted it already this week: no spoils until the reset.', 'helped')

if fails > 0 then os.exit(1) end
print('raid view tests OK (' .. checks .. ' checks)')
