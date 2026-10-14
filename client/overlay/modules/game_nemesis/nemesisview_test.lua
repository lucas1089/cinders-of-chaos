-- Self test of nemesisview.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/game_nemesis/nemesisview_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(here .. 'nemesisview.lua')
local V = NemesisView

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end
local function ok(cond, what) eq(cond and true or false, true, what) end

local P = V.plain

-- times
eq(P(V.ago(0)), 'just now', 'ago 0')
eq(P(V.ago(59)), 'just now', 'ago 59 s')
eq(P(V.ago(60)), '1 min ago', 'ago 1 min')
eq(P(V.ago(3599)), '59 min ago', 'ago 59 min')
eq(P(V.ago(7200)), '2 h ago', 'ago 2 h')
eq(P(V.ago(86400)), '1 day ago', 'ago 1 day')
eq(P(V.ago(3 * 86400 + 5)), '3 days ago', 'ago 3 days')
eq(P(V.ago(-5)), 'just now', 'ago negative')
eq(P(V.ago(0 / 0)), 'just now', 'ago NaN')
eq(V.ago(7200)[1], '%d h ago', 'ago is a pattern for tr()')
eq(P(V.left(13 * 86400)), '13 days', 'left days')
eq(P(V.left(86400)), '1 day', 'left one day')
eq(P(V.left(5 * 3600)), '5 h', 'left hours')
eq(P(V.left(10)), 'under an hour', 'left minutes')
eq(P(V.left('x')), 'under an hour', 'left garbage')
eq(P(V.subText('Ghoul', 1)), 'A Ghoul that killed you once', 'kills 1')
eq(P(V.subText('Ghoul', 2)), 'A Ghoul that killed you twice', 'kills 2')
eq(P(V.subText('Ghoul', 3)), 'A Ghoul that killed you three times', 'kills 3')
eq(P(V.subText('Ghoul', 7)), 'A Ghoul that killed you 7 times', 'kills 7')
eq(P(V.subText('Ghoul', 0)), 'A Ghoul that killed you once', 'kills 0')
eq(P(nil), '', 'plain nil')
eq(P({ '%d of %d', 1 }), '%d of %d', 'plain with a missing argument: the pattern, no error')

-- no nemesis
local v = V.build({ has = false, avenged = 2, hunted = 1 }, 1000)
eq(v.has, false, 'none')
eq(P(v.title), 'No Nemesis hunts you', 'empty title')
ok(P(v.empty):find('Avenger of Self', 1, true) ~= nil, 'empty text explains the reward')
eq(P(v.footer), 'Nemeses avenged: 2   |   Nemeses of others slain: 1', 'counters')
eq(#v.rows, 0, 'no rows')
v = V.build(nil, nil)
eq(v.has, false, 'nil state')
eq(P(v.footer), 'Nemeses avenged: 0   |   Nemeses of others slain: 0', 'nil counters')
v = V.build('garbage', 5)
eq(v.has, false, 'garbage state')

-- a nemesis
local NOW = 1800000000
local state = { has = true, name = 'Varkh', shown = 'Varkh, Twice-Slayer of Varek', monster = 'Ghoul', level = 125,
  kills = 2, lastSeen = NOW - 7200, created = NOW - 86400, expiresIn = 13 * 86400, avenged = 0, hunted = 3,
  traits = { { key = 'swift', name = 'Swift', desc = 'Much faster.' },
    { key = 'thorned', name = 'Thorned', desc = 'Reflects 15% of the damage it takes.' } } }
v = V.build(state, NOW)
eq(v.has, true, 'has')
eq(P(v.title), 'Varkh, Twice-Slayer of Varek', 'title = shown name')
eq(v.title[1], '%s', 'a name is a value, not a tr() key')
eq(P(v.sub), 'A Ghoul that killed you twice', 'sub')
eq(#v.rows, 5, 'five rows')
eq(P(v.rows[1][1]), 'Monster', 'row 1 label'); eq(P(v.rows[1][2]), 'Ghoul', 'type')
eq(P(v.rows[2][2]), '125', 'level')
eq(P(v.rows[3][2]), '2', 'kills')
eq(P(v.rows[4][2]), '2 h ago', 'last seen')
eq(P(v.rows[5][2]), '13 days', 'fades in')
eq(#v.traits, 2, 'two traits')
eq(v.traits[1].name, 'Swift', 'trait name'); eq(v.traits[1].color, '#70c8f0', 'trait colour')
eq(v.traits[2].desc, 'Reflects 15% of the damage it takes.', 'trait desc')
eq(P(v.footer), 'Nemeses avenged: 0   |   Nemeses of others slain: 3', 'footer')

-- pt-BR trait names from the server pass through
v = V.build({ has = true, name = 'Mok', monster = 'Ghoul', traits = { { key = 'swift', name = 'Veloz', desc = 'Muito mais rápido.' } } }, NOW)
eq(v.traits[1].name, 'Veloz', 'server text kept')
eq(P(v.title), 'Mok', 'no shown name: the base name')
eq(P(v.rows[4][2]), '?', 'no last seen')

-- malformed parts never break the view
v = V.build({ has = true, shown = string.rep('x', 500), monster = 42, level = 'high', kills = -3, lastSeen = 'y',
  traits = { 'bad', { name = 5 }, { key = 'nope', name = 'Odd' }, {}, { name = 'A' }, { name = 'B' }, { name = 'C' } } }, NOW)
eq(#P(v.title), V.MAX_TEXT, 'long name cut')
eq(P(v.rows[1][2]), '?', 'non-string type')
eq(P(v.rows[2][2]), '0', 'non-number level')
eq(P(v.rows[3][2]), '1', 'kills at least 1')
eq(#v.traits, 4, 'at most 4 traits, bad ones skipped')
eq(v.traits[1].name, 'Odd', 'first valid trait'); eq(v.traits[1].color, '#d6c9ae', 'unknown key colour')

-- every pattern the view gives to tr() is listed in V.PATTERNS (the pt-BR table needs each)
do
  local listed = {}
  for _, p in ipairs(V.PATTERNS) do listed[p] = true end
  local function seen(t, what)
    if type(t) == 'table' and t[1] ~= '%s' and t[1] ~= '%d' then ok(listed[t[1]], what .. ': ' .. tostring(t[1]) .. ' listed') end
  end
  for _, st in ipairs({ state, { has = false }, { has = true, kills = 9, lastSeen = NOW - 90000, expiresIn = 4000 } }) do
    local b = V.build(st, NOW)
    seen(b.title, 'title'); seen(b.sub, 'sub'); seen(b.empty, 'empty'); seen(b.footer, 'footer')
    for _, r in ipairs(b.rows) do seen(r[1], 'label'); seen(r[2], 'value') end
  end
  for _, sec in ipairs({ 0, 120, 7200, 86400, 200000 }) do seen(V.ago(sec), 'ago'); seen(V.left(sec), 'left') end
end

-- the trait colours cover every server trait key (nemesis_config.lua)
local f = io.open(here .. '../../../../server/data/scripts/chaos/nemesis_config.lua')
if f then
  local src = f:read('*a')
  f:close()
  local n = 0
  for key in src:gmatch('{key = "([%w_]+)", name = "[^"]+", pt = ') do
    n = n + 1
    ok(V.TRAIT_COLORS[key] ~= nil, 'colour for trait ' .. key)
  end
  eq(n, 5, 'five traits found in the server config')
  -- the opcode is the server's
  local c = io.open(here .. '../../../../server/data/scripts/chaos/chaos_constants.lua')
  local consts = c and c:read('*a') or ''
  if c then c:close() end
  ok(consts:find('ChaosOpcodes.nemesis = 163', 1, true) ~= nil, 'server opcode 163')
  local m = io.open(here .. 'nemesis.lua')
  local mod = m and m:read('*a') or ''
  if m then m:close() end
  ok(mod:find('local OPCODE = 163', 1, true) ~= nil, 'client opcode 163')
end

print(string.format('nemesisview_test: %d checks, %d failures', checks, failures))
if failures > 0 then os.exit(1) end
