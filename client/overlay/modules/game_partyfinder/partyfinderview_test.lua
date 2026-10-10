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

eq(V.queueText({ r = 'dps', since = 30 }, acts, 0), 'Queued as DPS (any activity) - just now', 'queue now')
eq(V.queueText({ r = 'healer', a = 'rift', since = 100 }, acts, 20), 'Queued as Healer (Rift) - 2m', 'queue rift')
eq(V.queueText(nil, acts, 0), '', 'not queued')
eq(V.applicantLine({ n = 'Seris', lv = 350, vn = 'Illusionist' }), 'Seris  Lv 350 Illusionist', 'applicant line')

if fails > 0 then print(fails .. ' failure(s)') os.exit(1) end
print('partyfinderview_test: OK')
