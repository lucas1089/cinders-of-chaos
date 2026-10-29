-- luajit nameplatemath_test.lua && lua5.3 nameplatemath_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'nameplatemath.lua')
local M = NameplateMath
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local l = M.parse('268435461|Administrator|e0402c|Omar|gold\n5|||Omar|\n6|Riftwalker|e8c15a||\nbad line\n7|x|zz||nope\n0|a|b|c|d')
eq(#l, 4, 'four plates')
eq(l[1].cid, 268435461, 'cid')
eq(l[1].title, 'Administrator', 'title')
eq(l[1].color, '#e0402c', 'colour')
eq(l[1].guild, 'Omar', 'guild')
eq(l[1].frame, 'gold', 'frame')
eq(l[2].title, nil, 'no title')
eq(l[2].frame, 'default', 'empty frame = default')
eq(l[3].guild, nil, 'no guild')
eq(l[4].color, M.TITLE_COLOR, 'bad colour')
eq(l[4].frame, 'default', 'unknown frame')
eq(#M.parse(nil), 0, 'nil buffer')
eq(#M.parse(''), 0, 'empty buffer')

eq(M.guildText('Omar'), '{Omar}', 'braces')
eq(M.guildText(nil), '', 'no guild')
eq(M.guildColor(2), M.WAR_GUILD_COLOR, 'war enemy')
eq(M.guildColor(1), M.GUILD_COLOR, 'ally')
eq(M.guildColor(0), M.GUILD_COLOR, 'none')
eq(M.framePath('crimson'), '/modules/game_nameplate/images/plate_crimson', 'frame path')
eq(M.framePath('x'), '/modules/game_nameplate/images/plate_default', 'unknown frame path')
eq(M.fallbackText({ title = 'Administrator', guild = 'Omar' }), 'Administrator\n{Omar}', 'fallback both')
eq(M.fallbackText({ guild = 'Omar' }), '{Omar}', 'fallback guild')
eq(M.fallbackText({}), '', 'fallback none')

eq(M.needsQuery(nil, 100, false), true, 'unknown')
eq(M.needsQuery(nil, 100, true), false, 'already asked')
eq(M.needsQuery({ at = 90 }, 100, false), false, 'cached')
eq(M.needsQuery({ at = 90, stale = true }, 100, false), false, 'stale but recent')
eq(M.needsQuery({ at = 30, stale = true }, 100, false), true, 'stale and old')

local q = {}
for i = 1, 65 do q[1000 + i] = true end
local msgs = M.queries(q)
eq(#msgs, 3, 'batched')
eq(msgs[1]:sub(1, 12), 'q|1001,1002,', 'first batch sorted')
eq(select(2, msgs[1]:gsub(',', ',')), 29, '30 ids in the first')
eq(msgs[3], 'q|1061,1062,1063,1064,1065', 'last batch')
eq(#M.queries({}), 0, 'nothing to ask')

local pend = { [1] = { at = 0, tries = 1 }, [2] = { at = 9, tries = 1 }, [3] = { at = 0, tries = 4 }, [4] = { at = 0, tries = 2 } }
local again = M.retries(pend, 10, function(id) return id ~= 4 end)
eq(#again, 1, 'one to ask again')
eq(again[1], 1, 'the old one')
eq(pend[2] ~= nil, true, 'recent one kept')
eq(pend[3], nil, 'given up after the last try')
eq(pend[4], nil, 'gone from the screen')

-- TRY ON of a store frame (O318)
local real = { cid = 7, title = 'Hunter', color = '#aabbcc', guild = 'Ash', frame = 'gold' }
local t = M.tryRecord(real, 'frost')
eq(t.frame, 'frost', 'the tried frame') eq(t.title, 'Hunter', 'title kept') eq(t.guild, 'Ash', 'guild kept')
eq(real.frame, 'gold', 'the real record is not changed')
eq(M.tryRecord(nil, 'frost').frame, 'frost', 'a player without a plate yet') eq(M.tryRecord(real, 'nope'), nil, 'unknown frame')
eq(M.tryRecord(real, 42), nil, 'not a name') eq(M.tryRecord(real, 'founder').frame, 'founder', 'a limited frame')
local a = M.beginTry(nil, 7, 'frost', 1000, 10000)
eq(a.token, 1, 'first token') eq(a.untilMs, 11000, 'ends after ten seconds') eq(M.beginTry(nil, 7, 'frost', 5).untilMs, 10005, 'default length')
eq(M.beginTry(a, 7, 'ember', 2000, 10000).token, 2, 'token grows') eq(M.beginTry(nil, 0, 'frost', 1), nil, 'no creature')
eq(M.beginTry(nil, 7, 'bad', 1), nil, 'no frame')
eq(M.tryActive(a, 10999), true, 'running') eq(M.tryActive(a, 11000), false, 'over') eq(M.tryActive(nil, 1), false, 'no try')
eq(M.shown(real, a, 7, 5000).frame, 'frost', 'own plate shows the try')
eq(M.shown(real, a, 7, 12000).frame, 'gold', 'restored after the time')
eq(M.shown(real, nil, 7, 1).frame, 'gold', 'no try')
local other = { cid = 8, frame = 'rose' }
eq(M.shown(other, a, 8, 5000), other, 'another player keeps own plate')
local b = M.beginTry(a, 7, 'ember', 2000, 10000)
eq(M.endTry(b, a.token), b, 'an old timer leaves the newer try') eq(M.endTry(b, b.token), nil, 'the newest timer ends it')
eq(M.endTry(nil, 1), nil, 'nothing to end')

if fails > 0 then error(fails .. ' failure(s)') end
print('nameplatemath_test: OK')
