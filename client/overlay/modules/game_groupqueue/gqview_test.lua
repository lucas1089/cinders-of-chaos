-- luajit gqview_test.lua && lua5.3 gqview_test.lua (CI runs it from the repository root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'gqview.lua')
local V = GqView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(V.clock(75), '1:15', 'clock'); eq(V.clock(-3), '0:00', 'clock never negative'); eq(V.clock(nil), '0:00', 'clock nil')

-- the arena buttons follow the party size
local solo = { enabled = true, leader = true, size = 1, inParty = false, arena = { order = { '1v1', '2v2', '3v3' } }, bg = { partyMax = 5 } }
local opts = V.arenaOptions(solo, { arena = '1v1' })
eq(#opts, 3, 'three arena modes')
eq(opts[1].enabled, true, '1v1 alone'); eq(opts[2].enabled, false, 'no 2v2 alone'); eq(opts[1].checked, true, 'checked')
eq(opts[2].tooltip, 'Arena 2v2: a party of exactly 2.', 'tooltip')
local duo = { enabled = true, leader = true, size = 2, inParty = true, bg = { partyMax = 5 } }
opts = V.arenaOptions(duo, {})
eq(opts[2].enabled, true, '2v2 as two'); eq(opts[1].enabled, false, 'no 1v1 in a party'); eq(opts[3].enabled, false, 'no 3v3 as two')
local member = { enabled = true, leader = false, size = 2, inParty = true }
eq(V.arenaOptions(member, {})[2].enabled, false, 'a member cannot pick')
eq(V.canEdit(member), false, 'a member cannot edit')
eq(V.canEdit({ enabled = true, leader = true, group = { picks = {} } }), false, 'queued: no edit')

-- difficulties
eq(#V.difficulties({ max = 3 }), 3, 'unlocked 1..3'); eq(V.difficulties({ max = 3, fixed = 4 })[1], 4, 'fixed')
eq(#V.difficulties(nil), 1, 'no dungeon: 1'); eq(#V.difficulties({ max = 0 }), 1, 'at least 1')

-- the request
local p = V.payload({ arena = '1v1', bg = true, dungeon = true, dungeonId = 3, difficulty = 2 })
eq(p.arena, '1v1', 'arena'); eq(p.bg, true, 'bg'); eq(p.dungeon.id, 3, 'dungeon id'); eq(p.dungeon.difficulty, 2, 'difficulty')
p = V.payload({ bg = false, dungeon = false, dungeonId = 3 })
eq(p.bg, nil, 'no bg'); eq(p.dungeon, nil, 'dungeon unticked')
eq(V.payload({ dungeon = true }).dungeon, nil, 'dungeon without an id')
eq(next(V.payload(nil)), nil, 'nil choice')

-- the Join button
local ok, why = V.joinable(solo, {})
eq(ok, false, 'nothing picked'); eq(why, 'Pick at least one queue.', 'reason')
eq((V.joinable(solo, { arena = '1v1' })), true, '1v1 alone')
ok, why = V.joinable(solo, { arena = '2v2' })
eq(ok, false, '2v2 alone refused')
eq((V.joinable(member, { bg = true })), false, 'a member cannot join')
eq(select(2, V.joinable(member, { bg = true })), 'Only the party leader can queue the party.', 'member reason')
eq((V.joinable({ enabled = true, leader = true, size = 6, bg = { partyMax = 5 } }, { bg = true })), false, 'too large')
eq((V.joinable({ enabled = false, leader = true, size = 1 }, { bg = true })), false, 'closed')
eq((V.joinable(nil, { bg = true })), false, 'no state')
eq((V.joinable({ enabled = true, leader = true, size = 1, group = {} }, { bg = true })), false, 'already queued')

-- status lines
local lines = V.statusLines(solo, 0)
eq(lines[1].text, 'Not queued.', 'not queued')
lines = V.statusLines(member, 0)
eq(lines[2].text, 'Your party leader picks the queues.', 'member hint')
local q = { enabled = true, leader = true, size = 2, group = { waited = 50, picks = { { key = 'arena', label = 'Arena 2v2' },
  { key = 'bg', label = 'Battleground' } }, check = { key = 'arena', label = 'Arena 2v2', accepted = 1, total = 2 } } }
lines = V.statusLines(q, 15)
eq(lines[1].text, 'Queued for: Arena 2v2, Battleground', 'queued for')
eq(lines[2].text, 'Waiting 1:05', 'waiting counts on')
eq(lines[3].text, 'Ready check: Arena 2v2, 1 of 2 ready', 'check line')
q.group.check, q.group.ready = nil, 'arena'
eq(V.statusLines(q, 0)[3].text, 'Everyone is ready: the match starts as soon as it can.', 'ready line')
eq(#V.statusLines(nil), 0, 'no state: no lines')

-- the popup
local c = V.check({ key = 'bg', label = 'Battleground', left = 20, accepted = 1, total = 3, mine = true }, 5, 20)
eq(c.title, 'Battleground is ready to start', 'title'); eq(c.sub, '1 of 3 party members ready', 'sub')
eq(c.left, 15, 'left'); eq(c.timer, '0:15', 'timer'); eq(c.percent, 75, 'percent'); eq(c.answered, true, 'answered')
eq(V.check({ left = 2 }, 9, 20).percent, 0, 'never below 0')
eq(V.check(nil), nil, 'no check')

print(string.format('gqview_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
