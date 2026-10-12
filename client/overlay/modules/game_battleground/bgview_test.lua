-- luajit bgview_test.lua && lua5.3 bgview_test.lua (CI runs it from the repository root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'bgview.lua')
local V = BgView
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- formatting
eq(V.clock(125), '2:05', 'clock'); eq(V.clock(-4), '0:00', 'clock never negative')
eq(V.number(1234567), '1,234,567', 'number'); eq(V.number(999), '999', 'small number'); eq(V.number(nil), '0', 'nil')
eq(V.span(45), '45s', 'span s'); eq(V.span(180), '3m', 'span m'); eq(V.span(7500), '2h 5m', 'span h')
eq(V.span(3 * 86400 + 4 * 3600), '3d 4h', 'span d'); eq(V.span(15 * 86400), '2w 1d', 'span w')
eq(V.delta(12), '+12', 'delta +'); eq(V.delta(-3), '-3', 'delta -')
eq((V.result('win')), 'VICTORY', 'result'); eq(select(2, V.result('loss')), '#e03a1e', 'result colour')

-- season cards
local tiers = { { key = 'ashen', name = 'Ashen', min = 0, honor = 200 }, { key = 'smoulder', name = 'Smouldering', min = 1400, honor = 400, title = 'Smouldering' },
  { key = 'kindled', name = 'Kindled', min = 1600, honor = 700, title = 'Kindled', frame = 'ember' },
  { key = 'blazing', name = 'Blazing', min = 1800, honor = 1000, title = 'Blazing', frame = 'crimson', cosmetics = { 'loot_blazing' } } }
local c = V.bracketCard({ name = 'Arena 2v2', rating = 1650, placed = true, tier = 3, tierName = 'Kindled', color = '#f0a040',
  wins = 7, losses = 2, draws = 1, rd = 90, matches = 10, peak = 1700 }, tiers, 5)
eq(c.tier, 'Kindled', 'placed tier'); eq(c.rating, '1650', 'rating'); eq(c.record, '7-2-1', 'record')
eq(c.image, '/images/chaos/battleground/tier_kindled', 'emblem')
c = V.bracketCard({ name = 'Battleground', rating = 1580, placed = false, placementLeft = 3 }, tiers, 5)
eq(c.tier, 'Placement 2/5', 'placement'); eq(c.rating, '?', 'hidden rating'); eq(c.unplaced, true, 'unplaced')
c = V.bracketCard({ rating = 2100, placed = true, tier = 4, tierName = 'Blazing', decayIn = 3 * 86400 }, tiers, 5)
eq(c.decay, 'Decay in 3d 0h without a rated match', 'decay warning')
eq(V.tierKey(tiers, 4), 'blazing', 'tier key'); eq(V.tierKey(nil, 2), 'ashen', 'tier key fallback')
local rows = V.rewardRows(tiers, 3)
eq(#rows, 4, 'reward rows'); eq(rows[1].text, '200 honor', 'ashen only honor'); eq(rows[1].from, 'below 1,400', 'ashen range')
eq(rows[4].text, 'title "Blazing (S3)", crimson plate frame, 1 cosmetic, 1,000 honor', 'blazing rewards')
eq(rows[3].from, '1,600+', 'kindled range')

-- queue window
local st = { minLevel = 100, bracket = { key = 'b2' }, waiting = 7, est = 95 }
eq(V.queueStatus(st, 0), '7 waiting in your bracket. Estimated wait: ~1m', 'idle status')
st.queue = { waited = 30, players = 12, est = 40 }
eq(V.queueStatus(st, 5), 'In the queue 0:35 (12 players waiting). Estimated: ~35s', 'queued status')
st.queue.est = 2
eq(V.queueStatus(st, 5), 'In the queue 0:35 (12 players waiting). Estimated: any moment', 'any moment')
st = { deserter = 600 }
eq(V.queueStatus(st, 0), 'Deserter: no queue for 10m.', 'deserter')
eq(V.queueStatus({ minLevel = 100 }, 0), 'You need level 100 for the battleground.', 'below level')
eq(V.queueStatus({ match = { phase = 'fight' } }, 0), 'You are in a battleground match.', 'in a match')
local roles = V.roleOptions({ roles = { 'tank', 'healer' }, role = 'healer' })
eq(#roles, 2, 'roles'); eq(roles[2].chosen, true, 'chosen role'); eq(roles[1].text, 'Tank', 'role name')
eq(V.honorLine({ honor = 1250, weekHonor = 300, weekCap = 6000, firstWinDone = true }),
  'Honor 1,250   (this week 300 / 6,000)   Weekly first win: taken', 'honor line')
local vr = V.vendorRow({ name = '50 great health potions', cost = 60, kind = 'item' }, 59)
eq(vr.can, false, 'too poor'); eq(vr.sub, 'You need 1 more honor.', 'how much more')
vr = V.vendorRow({ name = 'Kill effect', cost = 3000, kind = 'cosmetic', owned = true }, 9999)
eq(vr.button, 'Owned', 'owned cosmetic'); eq(vr.can, false, 'owned cannot buy')
vr = V.vendorRow({ name = 'Kill effect', cost = 3000, kind = 'cosmetic' }, 9999)
eq(vr.can, true, 'can buy'); eq(vr.button, '3,000 honor', 'price button')

-- HUD
eq(V.scorePercent(450, 1000), 45, 'score bar'); eq(V.scorePercent(1200, 1000), 100, 'score bar capped')
local teams, colors = { 'Emberguard', 'Ashbound' }, { '#ff9a3c', '#8fb8ff' }
local b = V.brazierState({ name = 'West Well', owner = 1, progress = 100 }, teams, colors)
eq(b.text, 'Emberguard', 'owned'); eq(b.color, '#ff9a3c', 'owner colour'); eq(b.image, '/images/chaos/battleground/well_1', 'owner icon')
b = V.brazierState({ name = 'Heart Well', owner = 0, progress = -40 }, teams, colors)
eq(b.text, '40% Ashbound', 'capturing'); eq(b.image, '/images/chaos/battleground/well_0', 'neutral icon')
b = V.brazierState({ owner = 2, progress = -100, contested = true }, teams, colors)
eq(b.text, 'contested', 'contested')
b = V.brazierState({ owner = 1, progress = 60 }, teams, colors)
eq(b.text, 'Emberguard 60%', 'owned but losing ground')
eq((V.hudCenter({ phase = 'prep', left = 12 })), '12', 'prep clock')
eq(select(2, V.hudCenter({ phase = 'fight', left = 400 })), 'left', 'fight label')
eq((V.hudCenter({ phase = 'fight', left = 400 })), '6:40', 'fight clock')
eq((V.hudNotice({ respawn = 7 })), 'Downed: back with the next wave in 7s', 'respawn notice')
eq((V.hudNotice({ afk = 30 })), 'Inactive: move or fight within 30s', 'afk notice')
eq((V.hudNotice({})), '', 'no notice')

-- scoreboard and summary
local sides = V.boardSides({ { name = 'A', team = 2, kills = 3, role = 'tank' }, { name = 'B', team = 1, damage = 12000, left = true } }, 2)
eq(#sides[1], 1, 'own team first'); eq(sides[1][1].name, 'A', 'own row'); eq(sides[1][1].role, 'Tank', 'role')
eq(sides[2][1].name, 'B (left)', 'deserter marked'); eq(sides[2][1].damage, '12,000', 'damage formatted')
local s = V.summary({ result = 'win', team = 2, teams = teams, score = { 610, 1004 }, reason = 'score', honor = 434, firstWin = true,
  season = { before = 1500, after = 1612, delta = 112, placed = false, placementLeft = 4 } })
eq(s.title, 'VICTORY', 'summary title'); eq(s.score, 'Ashbound 1004  -  610 Emberguard', 'summary score (own first)')
eq(s.rating, 'Season rating 1500 -> 1612 (+112)  (placement: 4 left)', 'summary rating')
eq(s.honor, 'Honor +434 (first win of the week)', 'summary honor'); eq(s.reason, 'first to the goal', 'reason')
eq(V.summary({ result = 'draw', rated = false }).rating, 'Not rated', 'unrated')

print(string.format('bgview_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
