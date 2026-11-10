-- luajit partyfinderview_test.lua && lua5.3 partyfinderview_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'partyfinderview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = PartyFinderView

V.setRoles({ { k = 'tank', n = 'Tank', c = '#111111' }, { k = 'healer', n = 'Healer' }, { k = 'dps', n = 'DPS' } })
eq(V.roleColor('tank'), '#111111', 'server colour')
eq(V.roleColor('healer'), '#6fd8a8', 'default colour kept')
eq(V.roleName('dps'), 'DPS', 'role name')
eq(V.roleLetter('healer'), 'H', 'letter')
eq(V.roleName(nil), '?', 'no role')

eq(V.timeLeft(3725), '1h 02m', 'hours')
eq(V.timeLeft(125), '2m', 'minutes')
eq(V.timeLeft(45), '45s', 'seconds')
eq(V.timeLeft(-5), '0s', 'never negative')
eq(V.ago(30), 'just now', 'ago now')
eq(V.ago(600), '10m ago', 'ago minutes')
eq(V.ago(7300), '2h ago', 'ago hours')
eq(V.badgeText(0), '', 'no badge')
eq(V.badgeText(3), '3', 'badge')
eq(V.badgeText(12), '9+', 'badge cap')

local row = {
  id = 7, a = 'rift', an = 'Rift T5-8', ld = 'Brannoc', ml = 300, left = 3000, note = 'fast',
  comp = { { n = 'Brannoc', lv = 400, vn = 'Juggernaut', r = 'tank', st = 'leader' },
    { n = 'Seris', lv = 350, vn = 'Illusionist', r = 'healer', st = 'invited' } },
  open = { tank = 0, healer = 0, dps = 2 },
}
local slots = V.slots(row)
eq(#slots, 4, 'two members and two open')
eq(slots[1].name, 'Brannoc', 'leader first')
eq(slots[3].filled, false, 'open slot')
eq(slots[3].role, 'dps', 'open dps')
eq(V.openTotal(row), 2, 'open total')
eq(V.openText(row), 'Needs 2 DPS', 'open text')
eq(V.openText({ open = { tank = 1, healer = 1, dps = 0 } }), 'Needs 1 Tank, 1 Healer', 'two roles')
eq(V.openText({ open = {} }), 'Full', 'full')
eq(V.compTooltip(row), 'Brannoc, level 400 Juggernaut (Tank) - leader\nSeris, level 350 Illusionist (Healer) - invited\n' ..
  'Open: DPS\nOpen: DPS', 'tooltip')
eq(#V.slots(nil), 0, 'no row')

eq(#V.applyRoles(row, { 'healer', 'dps' }), 1, 'only dps open for a Mystic')
eq(V.applyRoles(row, { 'healer', 'dps' })[1], 'dps', 'dps')
local ok, why = V.canApply(row, { 'dps' }, 320)
eq(ok, true, 'can apply')
ok, why = V.canApply(row, { 'dps' }, 200)
eq(why, 'Level 300+', 'level too low')
ok, why = V.canApply(row, { 'tank' }, 400)
eq(why, 'No open role for you', 'no role')
ok, why = V.canApply({ mine = true }, { 'dps' }, 400)
eq(why, 'Your group', 'own')
ok, why = V.canApply({ ap = 'dps', open = { dps = 1 } }, { 'dps' }, 400)
eq(why, 'Applied', 'applied')

local rows = {
  { id = 1, a = 'rift', ml = 100, open = { dps = 1 } },
  { id = 2, a = 'tower', ml = 500, open = { healer = 1 } },
  { id = 3, a = 'rift', ml = 1, open = { tank = 1 }, ap = 'tank' },
  { id = 4, a = 'omen', ml = 900, open = {}, mine = true },
}
local f = V.filter(rows, {}, 300)
eq(#f, 4, 'no filter')
eq(f[1].id, 4, 'own first')
eq(f[2].id, 3, 'applied next')
eq(f[3].id, 1, 'then server order')
f = V.filter(rows, { a = 'rift' }, 300)
eq(#f, 3, 'activity filter keeps own')
f = V.filter(rows, { role = 'healer' }, 300)
eq(#f, 2, 'role filter')
eq(f[2].id, 2, 'the healer slot')
f = V.filter(rows, { fits = true }, 300)
eq(#f, 3, 'level filter')
eq(#V.filter(nil, {}, 1), 0, 'nothing')

eq(V.subLine(row, 60), 'Brannoc  -  Lv 300+  -  49m left', 'sub line')
eq(V.subLine({ ld = 'X', ml = 1, left = 30, season = true }, 0), 'X  -  30s left  -  Season', 'season sub line')

local acts = {
  { k = 'rift', n = 'Rift', range = { min = 1, max = 15, label = 'Tier', short = 'T' } },
  { k = 'omen', n = 'Omen', targets = { 'A', 'B', 'C' } },
  { k = 'raid', n = 'Raid' },
  { k = 'other', n = 'Other', title = true },
}
eq(V.formKind(acts[1]), 'range', 'range kind')
eq(V.formKind(acts[2]), 'targets', 'targets kind')
eq(V.formKind(acts[3]), 'none', 'plain kind')
eq(V.formKind(acts[4]), 'title', 'title kind')
eq(V.formKind(nil), 'none', 'no activity')
local input = V.postInput(acts, { a = 'rift', lo = '0', hi = '99', tank = '1', healer = 'x', dps = 2, minLevel = '250',
  note = 'hi', exp = 30, role = 'tank', auto = true })
eq(input.lo, 1, 'lo clamped')
eq(input.hi, 15, 'hi clamped')
eq(input.want.healer, 0, 'bad number -> 0')
eq(input.want.dps, 2, 'dps')
eq(input.minLevel, 250, 'min level')
eq(input.auto, true, 'auto')
eq(input.t, nil, 'no target for a range')
input = V.postInput(acts, { a = 'rift', lo = '9', hi = '3' })
eq(input.hi, 9, 'hi not under lo')
eq(input.minLevel, 1, 'default min level')
input = V.postInput(acts, { a = 'omen', t = 2 })
eq(input.t, 2, 'target')
input = V.postInput(acts, { a = 'other', title = 'Quest' })
eq(input.title, 'Quest', 'title')
eq(V.formSize({ tank = 1, healer = '2', dps = 3 }), 7, 'form size')

-- a raid listing holds 15 (server party_finder_config.lua raid maxParty / perRole); the slots wrap in rows
local raidAct = { k = 'raid', n = 'Raid', max = 15, per = { tank = 3, healer = 4, dps = 12 },
  suggest = { tank = 2, healer = 3, dps = 9 } }
local lim = V.limits(raidAct, { party = 10, perRole = 6 })
eq(lim.max, 15, 'raid max')
eq(lim.per.tank, 3, 'raid tanks')
eq(lim.per.healer, 4, 'raid healers')
eq(lim.per.dps, 12, 'raid dps')
lim = V.limits({ k = 'rift' }, { party = 10, perRole = 6 })
eq(lim.max, 10, 'old server: lim.party')
eq(lim.per.dps, 6, 'old server: lim.perRole')
lim = V.limits(nil, nil)
eq(lim.max, 10, 'no activity: 10')
eq(lim.per.healer, 6, 'no activity: 6')
eq(V.formSize(raidAct.suggest), 15, 'the raid suggestion is 15')
local cols, rows = V.slotGrid(15, 10)
eq(cols, 8, '15 slots: 8 columns')
eq(rows, 2, '15 slots: 2 rows')
cols, rows = V.slotGrid(10, 10)
eq(cols, 10, '10 slots: one line')
eq(rows, 1, '10 slots: one row')
cols, rows = V.slotGrid(11, 10)
eq(cols * rows >= 11 and cols, 6, '11 slots: 6 + 5')
cols, rows = V.slotGrid(3, 10)
eq(cols, 3, '3 slots')
cols, rows = V.slotGrid(0, 10)
eq(rows, 1, 'no slot: one row')
local raidRow = { comp = { { n = 'Lead', lv = 900, vn = 'Juggernaut', r = 'tank', st = 'leader' } },
  open = { tank = 1, healer = 3, dps = 10 }, max = 15 }
eq(#V.slots(raidRow), 15, 'raid row: 15 slots')
eq(V.slots(raidRow)[15].role, 'dps', 'last open slot dps')
eq(V.openText(raidRow), 'Needs 1 Tank, 3 Healer, 10 DPS', 'raid open text')

eq(V.queueText({ r = 'dps', since = 30 }, acts, 0), 'Queued as DPS (any activity) - just now', 'queue now')
eq(V.queueText({ r = 'healer', a = 'rift', since = 100 }, acts, 20), 'Queued as Healer (Rift) - 2m', 'queue rift')
eq(V.queueText(nil, acts, 0), '', 'not queued')
eq(V.applicantLine({ n = 'Seris', lv = 350, vn = 'Illusionist' }), 'Seris  Lv 350 Illusionist', 'applicant line')
-- the mentor tags (server mentor.lua)
eq(V.applicantLine({ n = 'Ash', lv = 12, vn = 'Warrior', mt = 'seeking' }), 'Ash  Lv 12 Warrior  (Looking for mentor)', 'seeking tag')
eq(V.subLine({ ld = 'Brannoc', mt = 'mentor', left = 600 }, 0):find('Brannoc  -  Mentoring', 1, true) ~= nil, true, 'mentor tag on the row')
eq(V.compTooltip({ comp = { { n = 'Brannoc', lv = 60, vn = 'Juggernaut', r = 'tank', st = 'leader', mt = 'mentor' } }, open = {} })
  :find('leader - Mentoring', 1, true) ~= nil, true, 'mentor tag in the tooltip')
eq(V.mentorTag(nil), nil, 'no tag')

-- O389: the level band (ml .. xl), the fixed notes, a hunt's band
local band = { id = 9, a = 'hunt', ml = 300, xl = 450, left = 600, ld = 'Rhea', open = { dps = 1 }, comp = {}, nk = 2, note = 'hi' }
eq(V.levelFits(band, 300), true, 'band: at the bottom')
eq(V.levelFits(band, 450), true, 'band: at the top')
eq(V.levelFits(band, 451), false, 'band: above')
eq(V.levelFits(band, 299), false, 'band: below')
eq(V.levelFits({ ml = 10 }, 2000), true, 'no top: any level above')
local okHi, whyHi = V.canApply(band, { 'dps' }, 500)
eq(okHi, false, 'above the band: no apply')
eq(whyHi, 'Level 300-450', 'band refusal text')
eq(V.canApply(band, { 'dps' }, 400), true, 'inside the band: apply')
eq(#V.filter({ band }, { fits = true }, 500), 0, 'fits filter drops a row above its band')
eq(#V.filter({ band }, { fits = false }, 500), 1, 'without the filter it shows')
eq(V.subLine(band, 0), 'Rhea  -  Lv 300-450  -  10m left', 'sub line with the band')
eq(V.bandShort({ ml = 1, xl = 50 }), 'Lv 1-50', 'band from level 1')
eq(V.noteText(band, { 'Relaxed', 'Fast clear' }), 'Fast clear  -  hi', 'fixed note and free note')
eq(V.noteText({ note = '' , nk = 1 }, { 'Relaxed' }), 'Relaxed', 'fixed note only')
eq(V.noteText({ note = 'x', nk = 5 }, { 'Relaxed' }), 'x', 'unknown fixed note left out')
eq(V.noteText({ note = 'x' }, nil), 'x', 'no notes list')
local hunt = { k = 'hunt', targets = { 'Low Moor', 'Ashen Caves' }, bands = { { 6, 20 }, { 300, 400 } } }
local lo, hi = V.targetBand(hunt, 2)
eq(lo .. '-' .. hi, '300-400', 'hunt band')
eq(V.targetBand(hunt, 0), nil, 'any hunt: no band')
eq(V.targetBand({ targets = { 'x' } }, 1), nil, 'no bands')
local inp = V.postInput({ hunt }, { a = 'hunt', t = 2, minLevel = '300', maxLevel = '200', nk = 3, role = 'dps' })
eq(inp.maxLevel, 300, 'band top never under the minimum')
eq(inp.nk, 3, 'fixed note index')
eq(V.postInput({ hunt }, { a = 'hunt', minLevel = '5', maxLevel = '' }).maxLevel, 0, 'empty top: none')

-- O445: support, the fourth role. The server's list sets the order, a server with three roles still works
V.setRoles({ { k = 'tank', n = 'Tank', c = '#7fb8e8' }, { k = 'healer', n = 'Healer', c = '#6fd8a8' }, { k = 'dps', n = 'DPS', c = '#e8846a' },
  { k = 'support', n = 'Support', c = '#c08ae8' } })
eq(#V.ROLE_ORDER, 4, 'four roles in order')
eq(V.ROLE_ORDER[4], 'support', 'support last')
eq(V.roleName('support'), 'Support', 'support name')
eq(V.roleLetter('support'), 'S', 'support letter')
eq(V.roleColor('support'), '#c08ae8', 'support colour')
for _, r in ipairs({ 'tank', 'healer', 'dps' }) do
  eq(V.roleColor(r) ~= V.roleColor('support'), true, 'support colour differs from ' .. r)
  eq(V.roleLetter(r) ~= V.roleLetter('support'), true, 'support letter differs from ' .. r)
end
eq(V.hasRole('support'), true, 'has support')
eq(V.hasRole('bard'), false, 'no bard')
local supRow = { comp = { { n = 'Seris', lv = 400, vn = 'Illusionist', r = 'support', st = 'leader' } },
  open = { tank = 0, healer = 1, dps = 1, support = 2 } }
eq(V.openTotal(supRow), 4, 'open total counts support')
eq(V.openText(supRow), 'Needs 1 Healer, 1 DPS, 2 Support', 'open text names support')
local supSlots = V.slots(supRow)
eq(#supSlots, 5, 'slots: member plus four open')
eq(supSlots[1].role, 'support', 'a support member keeps its role')
eq(supSlots[5].role, 'support', 'open support slots last')
eq(V.applyRoles(supRow, { 'healer', 'dps', 'support' })[3], 'support', 'a support class may apply as support')
eq(#V.applyRoles({ open = { dps = 1 } }, { 'dps', 'support' }), 1, 'no open support: one role to apply as')
local sIn = V.postInput(acts, { a = 'rift', lo = '1', hi = '2', tank = 0, healer = 1, dps = 2, support = 2, role = 'dps' })
eq(sIn.want.support, 2, 'post input carries support')
eq(V.postInput(acts, { a = 'rift', lo = '1', hi = '2', dps = 1 }).want.support, 0, 'no support box: 0')
eq(V.formSize({ tank = 1, healer = 1, dps = 1, support = 2 }), 6, 'form size counts support')
local sLim = V.limits(raidAct, { party = 10, perRole = 6 })
eq(sLim.per.support, 6, 'support cap falls back to lim.perRole')
sLim = V.limits({ k = 'raid', max = 15, per = { tank = 3, healer = 4, dps = 12, support = 4 } }, nil)
eq(sLim.per.support, 4, 'raid support cap from the server')
eq(V.queueText({ r = 'support', a = nil, since = 0 }, acts, 0):find('Support', 1, true) ~= nil, true, 'queue text names support')
-- the role filter keeps a group that still needs a support
local fl = V.filter({ { a = 'rift', open = { support = 1 } }, { a = 'rift', open = { dps = 1 } } }, { role = 'support' }, 300)
eq(#fl, 1, 'role filter: support')
-- a server with three roles (older than O445): the order is its list, support is not offered
V.setRoles({ { k = 'tank', n = 'Tank' }, { k = 'healer', n = 'Healer' }, { k = 'dps', n = 'DPS' } })
eq(#V.ROLE_ORDER, 3, 'older server: three roles')
eq(V.hasRole('support'), false, 'older server: no support box')
eq(V.openText({ open = { support = 2 } }), 'Full', 'older server: support slots are not drawn')
-- an unknown role key from a newer server draws with a letter and the default colour, never an error
V.setRoles({ { k = 'tank', n = 'Tank' }, { k = 'scout', n = 'Scout' } })
eq(V.roleName('scout'), 'Scout', 'unknown role: name')
eq(V.roleLetter('scout'), 'S', 'unknown role: letter')
eq(V.roleColor('scout'), V.COLORS.text, 'unknown role: default colour')
eq(V.roleLetter('nothing'), '?', 'a role nobody sent: ?')
eq(V.roleColor('nothing'), V.COLORS.text, 'a role nobody sent: default colour')
V.setRoles({})
eq(#V.ROLE_ORDER, 2, 'an empty list keeps the last order')

if fails > 0 then print(fails .. ' failure(s)') os.exit(1) end
print('partyfinderview_test: OK')
