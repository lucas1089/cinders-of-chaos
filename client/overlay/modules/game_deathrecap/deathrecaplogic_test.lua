-- Self test of deathrecaplogic.lua (no client needed). Run from the repository root (CI runs it with luajit and lua5.3):
--   luajit client/overlay/modules/game_deathrecap/deathrecaplogic_test.lua
local here = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
-- the short number rule of the whole client (client_chaos_numbers loads first in the client)
dofile(here .. '../client_chaos_numbers/numbers.lua')
dofile(here .. 'deathrecaplogic.lua')
local L = DeathRecapLogic

local failures, checks = 0, 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(string.format('FAIL %s: got %q, want %q', what, tostring(got), tostring(want)))
  end
end
local function ok(cond, what) eq(cond and true or false, true, what) end

-- settings
eq(L.sanitize(nil).autoOpen, true, 'auto open by default')
eq(L.sanitize({ autoOpen = false }).autoOpen, false, 'auto open off kept')
eq(L.sanitize({ autoOpen = 'no' }).autoOpen, true, 'bad value -> default')

-- numbers: the damage abbreviation of client_chaos_numbers
eq(L.short(1150), '1.15k', 'short 1150')
eq(L.short(150000), '150k', 'short 150k')
eq(L.short(2459999), '2.45M', 'short 2.45M')
eq(L.short(999), '999', 'short below 1000')
eq(L.short(nil), '0', 'short nil')
eq(L.short(1234.9), formatShortNumber(1234), 'short floors like the damage numbers')
eq(L.exact(1234567), '1,234,567', 'exact')
eq(L.percent(1, 3), 33.3, 'percent')
eq(L.percent(1, 2), 50, 'percent whole')
eq(L.percent(1, 0), 0, 'percent of 0')
eq(L.seconds(4200), '4.2 s', 'seconds')
eq(L.seconds(800), '0.8 s', 'under a second')
eq(L.seconds(65000), '1:05', 'minutes')
eq(L.seconds(-5), '0.0 s', 'negative')
eq(L.clock(0), '?', 'no time')
ok(L.clock(1700000000):match('^%d%d %a+ %d%d:%d%d$') ~= nil, 'clock format')
eq(L.displayName('War Wolf', 'Varek'), 'War Wolf (Varek)', 'summon name')
eq(L.displayName(nil), 'Unknown', 'no name')
eq(L.elementName('lifedrain'), 'Life drain', 'element name')
eq(L.elementName('weird'), 'Other', 'unknown element')

-- outfit
local o = L.outfit({ type = 128, head = 78, addons = 7 })
eq(o.type, 128, 'outfit type')
eq(o.addons, 0, 'addons out of range -> 0')
eq(L.outfit({ type = 0 }), nil, 'no outfit')
eq(L.outfit({ auxType = 2160 }).auxType, 2160, 'item outfit')
eq(L.outfit('x'), nil, 'bad outfit')

-- a recap as the server sends it
local recap = {
  v = 1, at = 1700000000, real = 1, lvl = 120, xl = 150000, ll = 1, dur = 4200, win = 20000, tot = 1100, hp = 980, mp = 120,
  nh = 8, pvp = 1, mode = nil,
  kb = { n = 'Dragon', kind = 'c', el = 'fire', a = 250 },
  el = { fire = 630, energy = 230, manadrain = 40, physical = 200 },
  att = {
    { n = 'Varek', kind = 'u', tot = 270, hp = 150, mp = 120, h = 3, c = 1, x = 120, el = { energy = 230, manadrain = 40 } },
    { n = 'Others', kind = 'o', tot = 900, hp = 900, mp = 0, h = 9, c = 0, x = 200, el = { physical = 900 } },
    { n = 'Dragon', kind = 'c', tot = 750, hp = 750, mp = 0, h = 3, c = 1, x = 300, el = { fire = 550, physical = 200 },
      look = { type = 34 } },
    { n = 'Fire Elemental', m = 'Varek', kind = 'c', tot = 60, hp = 60, mp = 0, h = 1, c = 0, x = 60, el = { fire = 60 } },
    { n = 'Environment', kind = 'e', tot = 20, hp = 20, mp = 0, h = 1, c = 0, x = 20, el = {} },
  },
  last = { { dt = 1700, n = 'Varek', el = 'energy', a = 80, mp = 1 }, { dt = 0, n = 'Dragon', el = 'fire', a = 250, c = 1 } },
}
local rows = L.rows(recap)
eq(#rows, 5, 'five rows')
eq(rows[1].name, 'Dragon', 'most damage first')
eq(rows[5].name, 'Others', 'Others always last')
eq(rows[2].name, 'Varek', 'then the player')
eq(rows[3].name, 'Fire Elemental (Varek)', 'summon with its master')
eq(rows[5].frac, 1, 'bar: the biggest row is full, Others too')
ok(math.abs(rows[1].frac - 750 / 900) < 1e-9, 'bar of the others relative to it')
eq(rows[1].pct, 68.2, 'share of all damage')
eq(rows[1].critPct, 33, 'crit rate')
eq(rows[1].outfit.type, 34, 'outfit')
eq(rows[1].kindName, 'Monster', 'kind name')
eq(rows[2].kindName, 'Player', 'player kind')
eq(rows[1].elText, 'Fire 550, Physical 200', 'element text, largest first')
eq(rows[2].mp, 120, 'mana damage')
eq(rows[4].elText, '', 'no elements')
local els = L.elements({ fire = 550, physical = 200, ice = 0 })
eq(#els, 2, 'zero element left out')
eq(els[1].key, 'fire', 'element order')
eq(els[1].pct, 73.3, 'element share')
local seg = L.segments(rows[1])
eq(#seg, 2, 'bar segments')
ok(math.abs(seg[1].frac + seg[2].frac - 1) < 1e-9, 'segments fill the bar')
eq(#L.rows(nil), 0, 'no recap no rows')
eq(#L.rows({ att = { 'x' } }), 0, 'bad rows skipped')

-- header
local h = L.header(recap)
eq(h.title, 'Killed by Dragon', 'title')
ok(h.sub:find('level 120', 1, true) ~= nil and h.sub:find('PvP', 1, true) ~= nil, 'sub line')
eq(h.loss, 'Lost 150k experience and 1 level', 'loss')
eq(h.window, 'Last 4.2 s before the death, 8 hits', 'window')
eq(h.totals, 'Damage taken: 1.1k (health 980, mana 120)', 'totals')
eq(L.header({ real = 0, kb = { n = 'Varek' }, mode = 'Arena', tot = 0 }).title, 'Defeated by Varek', 'defeat title')
eq(L.header({ real = 0, kb = { n = 'Varek' }, mode = 'Arena' }).loss, 'Nothing lost', 'defeat loses nothing')
ok(L.header({ real = 0, mode = 'Arena' }).sub:find('Arena', 1, true) ~= nil, 'mode in the sub line')
eq(L.header({ real = 1, kb = { n = 'x' } }).loss, 'Experience lost: shown at your next login', 'loss not known yet')
eq(L.header({ real = 1, xl = 0, ll = 0 }).loss, 'No experience lost', 'no loss')
eq(L.header({ real = 1, xl = 5000, ll = 3 }).loss, 'Lost 5k experience and 3 levels', 'levels plural')
eq(L.header({}).window, 'No hits recorded before the death', 'no hits')
eq(L.header(nil).title, 'Killed by Unknown', 'nil recap')
eq(L.killingBlow(recap), 'Killing blow: Dragon, 250 fire', 'killing blow')
eq(L.killingBlow({ kb = { n = 'Varek', a = 99, el = 'energy', c = 1 } }), 'Killing blow: Varek, 99 energy (critical)', 'crit blow')
eq(L.killingBlow({ kb = { n = 'Demon' } }), 'Killing blow: Demon', 'blow without hits')

-- timeline
local tl = L.timeline(recap)
eq(#tl, 2, 'timeline length')
eq(tl[1].time, '-1.7 s', 'time before death')
eq(tl[2].time, 'death', 'killing blow at the death')
eq(tl[1].text, '-1.7 s  Varek  80 energy (mana)', 'timeline text')
eq(tl[2].text, 'death  Dragon  250 fire (critical)', 'timeline crit')
eq(L.timeline({ last = { { dt = 8, n = 'Dragon', a = 1 } } })[1].time, 'death', 'a hit a few ms before the death is the death')
eq(L.timeline({ last = { { dt = 100, n = 'Dragon', a = 1 } } })[1].time, '-0.1 s', '100 ms before')

-- history
local list = {
  { id = 12, at = 1700000300, k = 'Dragon', lvl = 120, xl = 150000, ll = 1, real = 1 },
  { id = 11, at = 1700000200, k = 'Varek', real = 0, mode = 'Arena' },
  { id = 10, at = 1700000100, k = 'Rat', lvl = 8, xl = 0, real = 1 },
  { id = 'bad' },
}
local hr = L.historyRows(list, 11)
eq(#hr, 3, 'bad entry skipped')
eq(hr[1].sub, '-150k exp, -1 lvl', 'loss in the list')
eq(hr[2].sub, 'Arena', 'defeat mode in the list')
eq(hr[3].sub, 'Level 8', 'no loss: the level')
eq(hr[2].selected, true, 'selected')
eq(hr[1].selected, false, 'not selected')
eq(hr[1].killer, 'Dragon', 'killer')

print(string.format('deathrecaplogic_test: %s (%d checks)', failures == 0 and 'OK' or (failures .. ' FAILED'), checks))
if failures > 0 then os.exit(1) end
