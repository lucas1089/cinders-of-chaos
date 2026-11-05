-- run from the repo root: luajit client/overlay/modules/game_passivetree/trendsview_test.lua (and lua5.3)
local dir = arg[0]:match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/trendsview.lua')
local V = TrendsView
local function eq(a, b, m) if a ~= b then error((m or '') .. ' expected ' .. tostring(b) .. ' got ' .. tostring(a), 2) end end

eq(V.share(429), '42.9%'); eq(V.share(1000), '100%'); eq(V.share(0), '0%'); eq(V.share(5), '0.5%')
eq(V.share(nil), '0%'); eq(V.share(4000), '100%')
local row = {rank = 1, share = 429, count = 6, level = 210, keystones = 'Bulwark, Cleaving Arc', code = 'CB6-AAA',
  full = 'CC1-BBB'}
eq(V.rowText(row), '#1  42.9% of the class, 6 characters, average level 210\nKeystones: Bulwark, Cleaving Arc')
eq(V.rowText({rank = 2, share = 100, count = 3, level = 120, keystones = ''}),
  '#2  10% of the class, 3 characters, average level 120\nKeystones: no keystone')
eq(V.rowText('x'), '')
-- import: the full code first, the tree code else, nothing for junk
eq(V.importCode(row), 'CC1-BBB')
eq(V.importCode({code = 'CB6-AAA'}), 'CB6-AAA')
eq(V.importCode({code = 'hello', full = 'nope'}), nil)
eq(V.importCode(nil), nil)
-- class tabs
local classes = {{key = 4, name = 'Warrior'}, {key = 3, name = 'Ranger'}, {key = 1, name = 'Mystic'}}
eq(V.step(classes, 4, 1), 3); eq(V.step(classes, 1, 1), 4); eq(V.step(classes, 4, -1), 1)
eq(V.step(classes, 99, 1), 4); eq(V.step({}, 7, 1), 7)
-- info line
eq(V.info({at = 0}), 'No snapshot yet: the server counts the builds once a day.')
local at = os.time({year = 2026, month = 11, day = 4, hour = 12})
eq(V.info({at = at, total = 0, rows = {}}), 'Snapshot of 2026-11-04: no build of this class is played by enough characters yet.')
eq(V.info({at = at, total = 312, rows = {row}}), 'Snapshot of 2026-11-04: 312 active characters of this class (level 100+, last 7 days).')
-- rows: at most V.ROWS, junk dropped; no name or id is shown (none is sent)
local many = {}
for i = 1, 8 do
  many[i] = {rank = i, share = 10, count = 3, level = 100, code = 'CB6-A' .. i}
end
many[2] = {rank = 2}
local shown = V.rows({rows = many})
eq(#shown, V.ROWS); eq(shown[2].rank, 3)
eq(#V.rows(nil), 0)
for _, r in ipairs(shown) do
  eq(V.rowText(r):find('name', 1, true), nil)
end
print('trendsview_test: ok')
