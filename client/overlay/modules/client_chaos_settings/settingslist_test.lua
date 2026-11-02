-- Self test of settingslist.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/client_chaos_settings/settingslist_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(here .. 'settingslist.lua')
local S = ChaosSettings

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %s, want %s', what, tostring(got), tostring(want)))
  end
end
local function join(t) local o = {} for i, v in ipairs(t) do o[i] = tostring(v) end return table.concat(o, ',') end

-- S.list: both key kinds, in index order
eq(join(S.list({ 'a', 'b', 'c' })), 'a,b,c', 'plain list')
eq(join(S.list({ ['1'] = 'a', ['2'] = 'b', ['3'] = 'c' })), 'a,b,c', 'string keys')
eq(join(S.list({ ['10'] = 'j', ['2'] = 'b', ['1'] = 'a' })), 'a,b,j', 'numeric order, not text order; a gap is skipped')
eq(join(S.list({ [1] = 'int', ['1'] = 'str', ['2'] = 'b' })), 'int,b', 'an integer key wins over its string twin')
eq(join(S.list({ ['1'] = 'a', x = 'no', ['1.5'] = 'no', ['0'] = 'no', ['-1'] = 'no', [2.5] = 'no' })), 'a', 'other keys left out')
eq(#S.list(nil), 0, 'nil')
eq(#S.list('text'), 0, 'not a table')
eq(#S.list({ [S.LIST_MAX + 1] = 'far' }), 0, 'capped index')

-- S.roundTrip: the engine casts
local r = S.roundTrip({ list = { 'w1', 'w2' }, on = true, n = 5, s = '7', b = 'false', empty = {}, [true] = 'dropped' })
eq(r.list[1], nil, 'round trip: index 1 is gone')
eq(r.list['1'], 'w1', 'round trip: index 1 is the tag "1"')
eq(r.on, true, 'round trip: boolean typed')
eq(r.n, 5, 'round trip: number typed')
eq(r.s, 7, 'round trip: numeric string comes back a number')
eq(r.b, false, 'round trip: "false" comes back a boolean')
eq(r.empty, nil, 'round trip: empty table is nil')
eq(S.roundTrip({}), nil, 'round trip: empty node is nil')
local n = 0 for _ in pairs(r) do n = n + 1 end
eq(n, 5, 'round trip: a boolean key and the empty table are dropped')
local plain = 0 for _ in ipairs(r.list) do plain = plain + 1 end
eq(plain, 0, 'round trip: ipairs sees nothing (the bug)')
eq(join(S.list(r.list)), 'w1,w2', 'round trip: S.list reads it')

-- the mock: set then get, twice (a second relog keeps the list)
local g = S.mockSettings()
g.setNode('k', { rows = { { id = 3 }, { id = 4 } } })
local back = g.getNode('k')
g.setNode('k', back)
back = g.getNode('k')
local ids = {}
for _, row in ipairs(S.list(back.rows)) do ids[#ids + 1] = row.id end
eq(join(ids), '3,4', 'mock: a list of tables survives two round trips')
eq(g.getNode('missing'), nil, 'mock: unknown node is nil')

print(string.format('settingslist_test: %d checks, %d failures', checks, failures))
if failures > 0 then os.exit(1) end
