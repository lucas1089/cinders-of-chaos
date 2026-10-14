-- luajit monsterbarmech_test.lua && lua5.3 monsterbarmech_test.lua (CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'monsterbarmech.lua')
local M = MonsterBarMech
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(M.start(nil, 0), nil, 'no payload, no cast')
eq(M.start({ label = 'x' }, 0), nil, 'a payload without ms')
local c = M.start({ cid = 7, boss = 'Kaelgor', label = 'Meteor Rain', ms = 2500, kind = 'telegraph' }, 1000)
eq(c.endAt, 3500, 'ends at now + ms')
eq(M.state(c, 1000).progress, 0, 'empty at the start')
eq(M.fillWidth(c, 2250, 200), 100, 'half way: half the bar')
eq(M.text(c, 1000), 'Kaelgor: Meteor Rain 2.5s - move out', 'text with the time and the hint')
eq(M.text(c, 3400), 'Kaelgor: Meteor Rain 0.1s - move out', 'the last tenth')
eq(M.text(c, 3600), 'Kaelgor: Meteor Rain', 'after the hit: the name only')
eq(M.state(c, 3500 + M.HOLD_MS).visible, true, 'held a moment after the hit')
eq(M.state(c, 3501 + M.HOLD_MS).visible, false, 'then hidden')
eq(M.fillWidth(c, 9000, 200), 0, 'hidden: no fill')
local k = M.start({ cid = 7, label = 'Inferno', ms = 9000, kind = 'channel' }, 0)
eq(M.text(k, 0), 'Inferno 9.0s - kill the totem', 'a channel without the boss name')
eq(M.start({ label = 'a', ms = 1, kind = 'nonsense' }, 0).kind, 'telegraph', 'unknown kinds read as telegraph')
local i = M.pick(k, M.start({ cid = 7, label = 'Interrupted', ms = 0, kind = 'interrupted' }, 4000), 4000)
eq(i.label, 'Inferno', 'an interrupt keeps the cast name')
eq(M.text(i, 4000), 'Inferno - interrupted!', 'interrupted text')
eq(M.fillWidth(i, 4000, 120), 120, 'interrupted: a full grey bar')
eq(M.pick(k, nil, 0), k, 'nothing new: keep')
for kind in pairs(M.COLORS) do
  eq(type(M.HINTS[kind]), 'string', 'a hint for ' .. kind)
end

print(string.format('monsterbarmech_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
