-- luajit recordsview_test.lua && lua5.3 recordsview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'recordsview.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local V = RecordsView

-- the meta parts are joined, bad entries dropped
local st = V.addPart(nil, { cat = 'bosses', boards = { { key = 'omen', name = 'Omen Guardians', format = 'time',
  variants = { { key = 'storm', name = 'Thalcyra' }, { key = 'hollow', name = 'Morvane' } },
  sizes = { { key = 'solo', name = 'Solo' }, { key = 'small', name = '2-3' } }, byClass = true }, 'junk' } })
st = V.addPart(st, { cat = 'bosses', boards = { { key = 'raid', name = 'Sepulchre Clear', format = 'time' } } })
st = V.addPart(st, { cat = 'tower', boards = { { key = 'tower_floor', name = 'Highest Floor' } } })
st = V.addPart(st, 'junk')
eq(st.parts, 3, 'three good parts')
local meta = V.finish(st, { parts = 3, categories = { { key = 'bosses', name = 'Bosses' }, { key = 'tower', name = 'Infinity Tower' }, 5 },
  periods = { { key = 'week', name = 'This week' }, { key = 'season', name = 'Season' }, { key = 'all', name = 'All time' } },
  groups = { { key = 1, name = 'Knight' } }, season = { key = 'q20264', name = 'Q4 2026' } })
eq(meta.complete, true, 'every part arrived')
eq(#meta.categories, 4, 'two categories, the realm firsts and the own records')
eq(meta.categories[3].key, 'firsts', 'realm firsts after the boards')
eq(meta.categories[4].key, 'mine', 'my records last (O260)')
eq(#meta.categories[4].boards, 0, 'my records has no boards')
eq(#V.category(meta, 'bosses').boards, 2, 'bosses joined from two parts')
local b, c = V.board(meta, 'omen')
eq(c.key, 'bosses', 'category of a board')
eq(V.finish(st, { parts = 4 }).complete, false, 'a part missing')

-- filters
local sel = V.normalize(b, { period = 'all', variant = 'hollow', size = 'party', group = 1 }, meta.periods)
eq(sel.period, 'all', 'period kept')
eq(sel.variant, 'hollow', 'variant kept')
eq(sel.size, 'solo', 'unknown size -> the first')
eq(sel.group, 1, 'class kept on a byClass board')
sel = V.normalize(V.board(meta, 'raid'), sel, meta.periods)
eq(sel.variant, nil, 'no variant on the raid')
eq(sel.size, nil, 'no size on the raid')
eq(sel.group, nil, 'no class filter on the raid')
eq(sel.period, 'all', 'period kept across boards')
eq(V.normalize(b, { period = 'x' }, meta.periods).period, 'week', 'bad period -> week')
local req = V.request(b, V.normalize(b, {}, meta.periods))
eq(req.board .. req.variant .. req.size .. req.period, 'omenstormsoloweek', 'request')

-- texts
eq(V.valueText(245, 'time'), '4:05', 'm:ss')
eq(V.valueText(3725, 'time'), '1:02:05', 'h:mm:ss')
eq(V.valueText(4512, 'pct'), '45.12%', 'share')
eq(V.valueText(15), '15', 'plain')
eq(V.ownText(b, { own = { rank = 3, value = 245 }, total = 40 }), 'Your rank: #3 of 40   -   Best: 4:05', 'own row')
eq(V.ownText(b, {}), 'You have no result on this board in this view yet.', 'no own row')
eq(V.recordText(b, { record = 230 }), 'All-time record: 3:50', 'record line')
eq(V.recordText(b, { record = false }), 'No all-time record yet: be the first.', 'no record')
eq(V.dateText(0), '', 'no date')
eq(#V.dateText(os.time()), 10, 'date')

if fails > 0 then error(fails .. ' failure(s)') end
print('recordsview_test: all passed')
