-- luajit collectionlogic_test.lua && lua5.3 collectionlogic_test.lua (from anywhere; CI runs it from the repo root)
-- The Collection log window's logic (O753): the payload cleaned, the filter, the lines with group headers, the texts, the
-- pity lines; the module reads the same opcode as the server and has a $mobile rule, a close control and a menu card.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'collectionlogic.lua')
local L = CollectionLogLogic
local fails, n = 0, 0
local function eq(a, b, what)
  n = n + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(c and true or false, true, what) end
local function read(path)
  local f = io.open(path, 'r')
  if not f then return '' end
  local s = f:read('*a')
  f:close()
  return s
end

-- a server state in the shape of collection_log.lua X.payload
local payload = {
  owned = 2, seen = 1, total = 5,
  groups = { { k = 'pinnacle', l = 'Pinnacle bosses' }, { k = 'set:embers', l = 'Set: %s', a = 'Embers of the Pyre' },
    { k = 'hunt', l = 'Hunting uniques' }, 'junk', { k = 'hunt', l = 'twice' } },
  rows = {
    { i = 2216, c = 3216, n = 'Signet of the Drowned Crown', g = 'pinnacle', s = 2, k = 1, d = 1764547200 },
    { i = 3975, c = 4975, n = 'Emberwarden', g = 'set:embers', s = 0, k = 0, d = 0 },
    { i = 8892, c = 9892, n = 'Cindermail Coat', g = 'set:embers', s = 1, k = 0, d = 0 },
    { i = 2412, c = 3412, n = 'Nightfang Katana', g = 'hunt', s = 2, k = 3, d = 0 },
    { i = 9999, n = 'Lost Group Item', g = 'mystery', s = 7, k = -2 },
    'junk', { n = 'no id' },
  },
  pity = { { k = 'rift', l = 'Rift chest: set piece', d = 37, n = 114 }, { k = 'pinnacle_vhoss', l = 'Pinnacle: %s unique', a = 'Vhoss', d = 99, n = 8 },
    { l = 'no key' } },
}
local s = L.clean(payload)
eq(#s.rows, 5, 'five rows: junk and a row with no id left out')
eq(s.rows[5].state, 0, 'a bad state is not yet')
eq(s.rows[5].count, 0, 'a negative count is 0')
eq(s.rows[5].cid, 9999, 'no client id: the server id')
eq(#s.order, 3, 'three groups, a double and junk left out')
eq(s.groups['set:embers'].arg, 'Embers of the Pyre', 'the set name')
eq(#s.pity, 2, 'two pity rows')
eq(s.pity[2].done, 8, 'a count above n is shown at n')
eq(s.total, 5, 'total')
local e = L.clean(nil)
eq(#e.rows, 0, 'nil: empty')
eq(L.clean({ rows = {} }).total, 0, 'no rows: total 0')

-- the lines: a header per group with rows, in the server's order, then an unknown group
local lines = L.lines(s, 'all', '')
eq(lines[1].kind, 'header', 'a header first')
eq(lines[1].key, 'pinnacle', 'pinnacle first')
eq(lines[1].owned, 1, 'its owned')
eq(lines[3].key, 'set:embers', 'the set group')
eq(lines[3].total, 2, 'two pieces')
eq(lines[3].owned, 0, 'none owned')
eq(lines[#lines - 1].key, 'mystery', 'an unknown group comes last')
eq(#lines, 5 + 4, 'five rows and four headers')
lines = L.lines(s, 'owned', '')
eq(#lines, 4, 'owned: two groups, two rows')
lines = L.lines(s, 'seen', '')
eq(#lines, 2, 'seen: one group, one row')
eq(lines[2].row.name, 'Cindermail Coat', 'the seen row')
eq(lines[1].total, 2, 'the header still counts the whole group')
lines = L.lines(s, 'missing', '')
eq(#lines, 4, 'not yet: two groups, two rows')
lines = L.lines(s, 'all', '  KATANA ')
eq(#lines, 2, 'search: by name, any case, trimmed')
eq(#L.lines(s, 'all', 'nothing like it'), 0, 'search: nothing')
eq(#L.lines(nil, 'all', ''), 0, 'no state: no lines')

-- texts
local d = L.itemDetail(s.rows[1])
eq(d[1], 'x%d, first on %s', 'owned with a date')
eq(d[2], 1, 'the count')
eq(d[3], os.date('%d/%m/%Y', 1764547200), 'the date')
eq(L.itemDetail(s.rows[4])[1], 'x%d', 'owned without a date')
eq(L.itemDetail(s.rows[3])[1], 'Seen', 'seen')
eq(L.itemDetail(s.rows[2])[1], 'Not yet', 'not yet')
eq(L.dateText(0), '', 'no date')
eq(L.summary(nil)[1], 'Loading...', 'no state yet')
local sum = L.summary(s)
eq(sum[1], 'Owned %d of %d, seen %d', 'the summary')
eq(sum[2], 2, 'owned')
eq(sum[3], 5, 'of')
local pl = L.pityLines(s)
eq(pl[1].text, '37 / 114', 'the pity text')
eq(pl[2].arg, 'Vhoss', 'the pinnacle boss name')
eq(pl[2].ratio, 1, 'full')
eq(L.valueOf({ { 'owned', 'Owned', 'Obtidos' } }, 'Obtidos'), 'owned', 'the combo value by the shown text')
eq(L.valueOf({}, 'x'), 'all', 'unknown: all')

-- the module and the server agree on the opcode; the window can close, has a $mobile rule and a menu card
local root = dir .. '../../../../'
eq(L.OPCODE, 170, 'opcode 170')
ok(read(root .. 'server/data/scripts/chaos/chaos_constants.lua'):find('ChaosOpcodes.collectionLog = 170', 1, true), 'server opcode 170')
local otui = read(dir .. 'collectionlog.otui')
ok(otui:find('$mobile:', 1, true), 'a $mobile rule')
ok(otui:find("tr('Close')", 1, true) and otui:find('ChaosCloseX', 1, true), 'a close control')
ok(read(dir .. '../client_chaos_topbar/topbar_tree.lua'):find("'Collection Log'", 1, true), 'a card in the hub menu')
ok(read(dir .. 'collectionlog.lua'):find("'Collection Log'", 1, true), 'the module registers the entry')

print(string.format('collectionlogic_test: %d checks, %d failures', n, fails))
os.exit(fails == 0 and 0 or 1)
