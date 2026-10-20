-- run from the repo root: luajit client/overlay/modules/game_passivetree/statinfoview_test.lua (and lua5.3)
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/statinfoview.lua')
local V = StatInfoView
local function eq(a, b, m) if a ~= b then error((m or '') .. ' expected ' .. tostring(b) .. ' got ' .. tostring(a), 2) end end

local s = V.new()
s = V.add(s, {cls = 'knight', part = 1, parts = 2, header = {primary = 'Strength', secondary = 'Vitality, Armor'},
  stats = {{k = 'strength', n = 'Strength', d = 'More melee damage.', t = 'primary'}, {k = 'vitality', n = 'Vitality', d = 'More life.', t = 'secondary'}}})
s = V.add(s, {cls = 'knight', part = 2, parts = 2, stats = {{k = 'wisdom', n = 'Wisdom', d = 'More mana.'}, 'junk', {k = 5}}})
eq(s.got, 2); eq(#s.order, 3)
eq(V.tag(s, {strength = 3, wisdom = 1}), 'primary')
eq(V.tag(s, {wisdom = 1, vitality = 2}), 'secondary')
eq(V.tag(s, {wisdom = 1}), nil)
eq(V.tag(s, nil), nil)
eq(V.tag(s, {ksFlag = true}), nil)
eq(V.color('primary'), V.GOLD); eq(V.color('secondary'), V.SILVER); eq(V.color(nil), nil)
local l = V.lines(s, {strength = 1, vitality = 1, other = 4})
eq(#l, 2); eq(l[1], 'Strength: More melee damage.'); eq(l[2], 'Vitality: More life.')
eq(V.headerText(s), 'Primary: Strength   Secondary: Vitality, Armor')
eq(V.headerText(V.new()), '')
local rows = V.rows(s)
eq(rows[2].text, 'Strength [Primary]'); eq(rows[2].color, V.GOLD)
eq(rows[4].text, 'Vitality [Secondary]'); eq(rows[6].text, 'Wisdom'); eq(#rows, 7)
-- another class starts over; bad input changes nothing
local t = V.add(s, {cls = 'mage', part = 2, parts = 2, stats = {{k = 'x', n = 'X', d = ''}}})
eq(#t.order, 1); eq(t.byKey.strength, nil)
eq(V.add(s, 'bad'), s); eq(V.add(s, {stats = 4}), s)
print('statinfoview_test: ok')
