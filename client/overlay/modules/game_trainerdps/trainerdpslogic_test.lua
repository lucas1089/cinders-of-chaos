-- luajit trainerdpslogic_test.lua && lua5.3 trainerdpslogic_test.lua (CI runs it from the repo root)
-- The pure parts of the trainer DPS panel against the DPS meter's formats and a REAL view of the server's
-- trainer_meter_core.lua (so the client reads what the server sends).
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. '../game_dpsmeter/dpsmath.lua')
dofile(dir .. 'trainerdpslogic.lua')
dofile(dir .. '../../../../server/data/scripts/chaos/trainer_meter_core.lua')
local L, M = TrainerDpsLogic, ChaosTrainerMeterCore
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(v, what) eq(v and true or false, true, what) end

-- a real state from the server's core
local cfg = M.configure(dofile(dir .. '../../../../server/data/scripts/chaos/trainer_meter_config.lua'))
local T0 = 100000
local bolt = { k = 's:Witchfire Bolt', t = 's', n = 'Witchfire Bolt', i = 'exori flam' }
local sword = { k = 'w:Sword attacks', t = 'w', n = 'Sword attacks', i = 'sword' }
local burn = { k = 'd:Burning', t = 'd', n = 'Burning', i = 'burning' }
local s = M.newSession(3, 40, 'Training Dummy')
M.record(cfg, s, T0, 3000, bolt, 'fire', false)
M.record(cfg, s, T0 + 1000, 1500, sword, 'physical', true)
M.record(cfg, s, T0 + 2000, 4500, bolt, 'fire', false)
M.record(cfg, s, T0 + 3000, 1000, burn, 'fire', false)
local now = T0 + 4000
local state = M.view(cfg, s, now, { class = 'normal', level = nil })

-- settings
local st = L.sanitize(nil)
eq(st.auto, true, 'opens by itself by default')
eq(st.keep, false, 'does not keep by default')
eq(st.tab, 'src', 'skills tab')
eq(st.closeAfter, 15, 'hides 15 s after the end')
st = L.sanitize({ auto = false, keep = true, tab = 'el', closeAfter = 5000 })
eq(st.auto, false, 'auto kept')
eq(st.keep, true, 'keep kept')
eq(st.tab, 'el', 'tab kept')
eq(st.closeAfter, 300, 'delay capped')
eq(L.sanitize({ tab = 'nope', auto = 'yes', closeAfter = 'x' }).tab, 'src', 'unknown tab')
eq(L.sanitize({ auto = 'yes' }).auto, true, 'a bad boolean falls back')
eq(L.sanitize({ closeAfter = 1 }).closeAfter, 3, 'delay at least 3 s')
eq(L.tab('party').key, 'party', 'tab lookup')
eq(L.tab('zzz').key, 'src', 'unknown tab lookup')

-- when the panel opens and hides
do
  local auto = L.sanitize(nil)
  local r = L.onState({ visible = false, closeAt = nil, sid = nil }, state, auto, 1000)
  ok(r.open, 'a new running session opens the panel')
  eq(r.sid, 3, 'the session is remembered')
  eq(r.closeAt, nil, 'a running session never hides')
  -- the player closed it in the middle of the session: it stays closed
  r = L.onState({ visible = false, closeAt = nil, sid = 3 }, state, auto, 2000)
  ok(not r.open, 'a panel closed by the player stays closed during the same session')
  -- a new session opens it again
  local again = M.view(cfg, M.newSession(4, 40, 'Training Dummy'), now)
  again.act, again.empty = 1, 0
  r = L.onState({ visible = false, closeAt = nil, sid = 3 }, again, auto, 3000)
  ok(r.open, 'the next session opens it again')
  -- "open by itself" off: a running session does not open it, a shown panel stays
  local manual = L.sanitize({ auto = false })
  r = L.onState({ visible = false, closeAt = nil, sid = nil }, state, manual, 1000)
  ok(not r.open, 'auto off: stays closed')
  r = L.onState({ visible = true, closeAt = nil, sid = 3 }, state, manual, 1000)
  ok(r.open, 'auto off, panel shown: stays')
  -- the end: hides closeAfter seconds later, once
  M.tick(cfg, s, T0 + 3000 + 10000)
  local ended = M.view(cfg, s, T0 + 20000)
  eq(ended['end'], 1, 'the server says it ended')
  r = L.onState({ visible = true, closeAt = nil, sid = 3 }, ended, auto, 50000)
  eq(r.closeAt, 50000 + 15000, 'hides 15 s after the end')
  ok(r.open, 'the shown panel stays to show the result')
  local r2 = L.onState({ visible = true, closeAt = r.closeAt, sid = 3 }, ended, auto, 52000)
  eq(r2.closeAt, r.closeAt, 'a repeated final state does not push it back')
  ok(not L.shouldClose(r.closeAt, auto, 64999), 'not yet')
  ok(L.shouldClose(r.closeAt, auto, 65000), 'now')
  eq(L.secondsLeft(r.closeAt, 50000), 15, 'seconds left')
  eq(L.secondsLeft(r.closeAt, 64001), 1, 'seconds left, rounded up')
  eq(L.secondsLeft(r.closeAt, 70000), 0, 'never negative')
  eq(L.secondsLeft(nil, 1), nil, 'no hide pending')
  -- keep open: never hides
  local keep = L.sanitize({ keep = true })
  r = L.onState({ visible = true, closeAt = nil, sid = 3 }, ended, keep, 50000)
  eq(r.closeAt, nil, 'keep: no hide')
  ok(not L.shouldClose(1, keep, 99999999), 'keep: never closes')
  -- the panel is not shown when a session ends: nothing to hide
  r = L.onState({ visible = false, closeAt = nil, sid = 3 }, ended, auto, 50000)
  ok(not r.open and r.closeAt == nil, 'an ended session does not open a closed panel')
  -- a reset session: the panel stays as it is
  local empty = M.view(cfg, M.newSession(5, 40, 'Training Dummy'), now)
  r = L.onState({ visible = true, closeAt = 99, sid = 3 }, empty, auto, 1000)
  ok(r.open, 'reset: the shown panel stays')
  eq(r.closeAt, nil, 'reset: no hide pending')
  r = L.onState({ visible = false, closeAt = nil, sid = 3 }, empty, auto, 1000)
  ok(not r.open, 'reset: a closed panel stays closed')
  -- none, and garbage
  r = L.onState({ visible = true, closeAt = 77, sid = 3 }, { none = 1 }, auto, 1000)
  ok(not r.open and r.closeAt == 77 and r.sid == 3, 'none changes nothing')
  r = L.onState({ visible = true, closeAt = 77, sid = 3 }, 'x', auto, 1000)
  eq(r.closeAt, 77, 'garbage changes nothing')
end

-- the numbers
do
  local t = L.stats(state)
  eq(t.total, DpsMath.short(state.tot), 'total in short form')
  eq(t.total, '10k', 'total 10000')
  eq(t.cur, DpsMath.short(state.cur), 'DPS now')
  eq(t.avg, DpsMath.short(state.avg), 'average')
  eq(t.time, '0:04', 'time')
  eq(t.exactTotal, '10,000', 'exact total')
  ok(t.biggest:find('4.5k', 1, true) ~= nil and t.biggest:find('Witchfire Bolt', 1, true) ~= nil, 'biggest hit with its source: ' .. t.biggest)
  ok(t.hits:find('4 hits', 1, true) ~= nil and t.hits:find('25%', 1, true) ~= nil, 'hits and crit share: ' .. t.hits)
  local blank = L.stats(nil)
  eq(blank.total, '0', 'no state: zero')
  eq(blank.time, '0:00', 'no state: no time')
  eq(blank.biggest, '0', 'no state: no biggest hit')
  eq(L.status(nil), 'Hit a trainer to start.', 'status without a state')
  eq(L.status({ none = 1 }), 'Hit a trainer to start.', 'status with none')
  eq(L.status(M.view(cfg, M.newSession(1, 1, 'x'), now)), 'Reset. Hit the trainer to count again.', 'status after a reset')
  ok(L.status(state):find('10 s', 1, true) ~= nil, 'status while running names the silence that ends it')
  local ended = M.view(cfg, s, T0 + 99999)
  ok(L.status(ended, 12):find('12 s', 1, true) ~= nil, 'status when ended, with the seconds left')
  eq(L.status(ended, nil), 'Finished. This is the last result.', 'status when ended and kept')
  eq(L.profileText(state), 'Target: a normal monster of your level', 'target text: the player level')
  eq(L.profileText({ prof = { c = 'boss', l = 300 } }), 'Target: a boss monster of level 300', 'target text: a fixed level')
  eq(L.profileText({}), '', 'no profile: no text')
  eq(L.profileText(nil), '', 'no state: no text')
end

-- the rows
do
  local rows = L.skillRows(state)
  eq(#rows, 3, 'three skills')
  eq(rows[1].name, 'Witchfire Bolt', 'biggest first')
  eq(rows[1].total, 7500, 'its total')
  eq(rows[1].pct, 75, 'its share')
  eq(rows[1].hits, 2, 'hits')
  eq(rows[1].critPct, 0, 'no crits')
  eq(rows[1].avg, 3750, 'average hit')
  eq(rows[1].max, 4500, 'biggest hit')
  eq(rows[1].frac, 0.75, 'the bar is the share of the total damage')
  eq(rows[1].rate, math.floor(7500 * 1000 / 4000), 'per second over the session')
  eq(rows[2].name, 'Sword attacks', 'second')
  eq(rows[2].critPct, 100, 'a crit share')
  eq(rows[2].frac, 0.15, 'second bar: its share of the total')
  eq(rows[1].color, DpsMath.barColor('s', 1), 'colour by kind')
  local sum = 0
  for _, r in ipairs(rows) do sum = sum + r.total end
  eq(sum, state.tot, 'rows add up to the total')
  -- the "Others" row
  local c2 = M.configure({ maxRowsSent = 1 })
  local s2 = M.newSession(1, 1, 'x')
  M.record(c2, s2, T0, 100, bolt, 'fire')
  M.record(c2, s2, T0 + 1, 50, sword, 'physical')
  local r2 = L.skillRows(M.view(c2, s2, T0 + 1000))
  eq(#r2, 2, 'one row and the rest')
  eq(r2[2].name, 'Others', 'the rest is named Others')
  eq(#L.skillRows(nil), 0, 'no state: no rows')
  eq(#L.skillRows({}), 0, 'an empty state: no rows')
  local els = L.elementRows(state)
  eq(#els, 2, 'two elements')
  eq(els[1].element, 'fire', 'fire first')
  eq(els[1].total, 8500, 'fire total')
  eq(els[1].pct, 85, 'fire share')
  eq(els[1].name, 'Fire', 'element name')
  eq(els[1].frac, 0.85, 'element bar: its share')
  eq(els[1].color, L.ELEMENT_COLORS.fire, 'element colour')
  eq(els[2].name, 'Physical', 'second element')
  eq(#L.elementRows(nil), 0, 'no state: no elements')
  -- every element the server can send has a colour and a name
  for _, e in ipairs({ 'physical', 'fire', 'earth', 'energy', 'ice', 'holy', 'death', 'drown', 'lifedrain', 'manadrain' }) do
    ok(L.ELEMENT_COLORS[e] ~= nil, 'a colour for ' .. e)
    ok(DpsMath.ELEMENT_NAMES[e] ~= nil, 'a name for ' .. e)
  end
  -- the party
  ok(not L.hasParty(state), 'no party list: no party tab')
  local withParty = { party = { { n = 'Hero', cur = 900, tot = 9000, me = 1 }, { n = 'Mage', cur = 300, tot = 3000 } } }
  ok(L.hasParty(withParty), 'two members: the party tab')
  ok(not L.hasParty({ party = { { n = 'Solo', cur = 1, tot = 1, me = 1 } } }), 'one member is no party')
  local pr = L.partyRows(withParty)
  eq(#pr, 2, 'two rows')
  eq(pr[1].name, 'Hero', 'first')
  eq(pr[1].me, true, 'marked')
  eq(pr[1].pct, 75, 'share of the party')
  eq(pr[2].frac, 1 / 3, 'bar against the first')
  eq(pr[2].me, false, 'not marked')
  eq(#L.partyRows(nil), 0, 'no state: no rows')
end

-- the exports
do
  local text = L.summary(state)
  ok(text:find('Training Dummy', 1, true) ~= nil, 'the summary names the trainer')
  ok(text:find('Witchfire Bolt', 1, true) ~= nil, 'the summary lists the skills')
  ok(text:find('Fire 85%', 1, true) ~= nil, 'the summary lists the elements: ' .. text)
  ok(text:find('10,000', 1, true) ~= nil, 'the summary has exact numbers')
  eq(L.summary(nil), '', 'no state: nothing to copy')
  eq(L.summary({ none = 1 }), '', 'none: nothing to copy')
  eq(L.summary(M.view(cfg, M.newSession(1, 1, 'x'), now)), '', 'an empty session: nothing to copy')
  local line = L.chatLine(state, 240)
  ok(line:find('Training Dummy', 1, true) ~= nil and line:find('Witchfire Bolt 75%', 1, true) ~= nil, 'chat line: ' .. line)
  ok(#line <= 240, 'chat line within its limit')
  ok(#L.chatLine(state, 70) <= 70 + 0, 'a short limit is kept: ' .. #L.chatLine(state, 70))
  eq(L.chatLine(nil, 240), '', 'no state: no line')
end

-- the stats over time: a hit sequence through the real server core, read the way the panel reads it (a summary a second,
-- the clock between two of them by L.live)
do
  local function near(a, b, what) ok(math.abs(a - b) < 1e-6, what .. ': ' .. tostring(a) .. ' ~ ' .. tostring(b)) end
  -- one hit, then silence: the numbers fall with the clock, they do not stay at the size of the hit
  local one = M.newSession(7, 1, 'Training Dummy')
  M.record(cfg, one, T0, 178, sword, 'physical', false)
  local v0 = M.view(cfg, one, T0)
  eq(v0.tot, 178, 'one hit: total')
  eq(v0.dur, 0, 'one hit: time 0 at the hit')
  local v2 = M.view(cfg, one, T0 + 2000)
  eq(v2.tot, 178, 'one hit, 2 s later: total stays')
  eq(v2.dur, 2000, 'one hit, 2 s later: time ticks')
  eq(v2.cur, 89, 'one hit, 2 s later: DPS now is over the 2 s')
  eq(v2.avg, 89, 'one hit, 2 s later: average is over the 2 s')
  local v4 = M.view(cfg, one, T0 + 4000)
  eq(v4.cur, 45, 'one hit, 4 s later: DPS now keeps falling (44.5)')
  -- the panel's clock between two summaries
  local live = L.live(v0, 5000, 8000)
  eq(live.dur, 3000, 'live: the time ticks 3 s after the summary')
  eq(live.avg, 59, 'live: average is the total over the clock (178 / 3 s)')
  eq(live.tot, 178, 'live: total is the server\'s')
  eq(live.cur, v0.cur, 'live: DPS now is the server\'s')
  eq(v0.dur, 0, 'live: the state it was given is not changed')
  eq(L.live(v0, 5000, 5000), v0, 'live: no time passed, the same state')
  eq(L.live(v0, 5000, 4000), v0, 'live: a clock that went back changes nothing')
  eq(L.live(nil, 1, 2), nil, 'live: no state')
  eq(L.live({ none = 1 }, 1, 2).none, 1, 'live: none stays none')
  local ended = M.view(cfg, one, T0 + 20000)
  ok(M.tick(cfg, one, T0 + 20000), 'the session ends')
  ended = M.view(cfg, one, T0 + 20000)
  eq(L.live(ended, 1000, 9000), ended, 'live: a finished session does not tick')
  eq(ended.dur, 0, 'the finished time is first hit to last hit (one hit: 0)')
  eq(L.live(v0, 5000, 5500).avg, 178, 'live: under 1 s the average is over 1 s')

  -- steady hits: 100 damage every second for 8 s
  local st2 = M.newSession(8, 1, 'Training Dummy')
  for i = 0, 7 do M.record(cfg, st2, T0 + i * 1000, 100, bolt, 'fire', false) end
  local a = M.view(cfg, st2, T0 + 7000)
  eq(a.tot, 800, 'steady: total')
  eq(a.dur, 7000, 'steady: time')
  near(a.avg, math.floor(800 * 1000 / 7000 + 0.5), 'steady: average over the 7 s')
  -- the window holds 5 s: the hits of +3 .. +7 s (the hit of +2 s left at +7 s)
  eq(a.cur, 100, 'steady: DPS now is 100 a second, not the size of a hit')
  -- a pause: no hit for 4 s
  local b = M.view(cfg, st2, T0 + 11000)
  eq(b.tot, 800, 'pause: total unchanged')
  eq(b.dur, 11000, 'pause: the time keeps counting')
  eq(b.avg, math.floor(800 * 1000 / 11000 + 0.5), 'pause: the average falls')
  eq(b.cur, 20, 'pause: DPS now only holds the hit of +7 s (100 over 5 s)')
  local c = M.view(cfg, st2, T0 + 13000)
  eq(c.cur, 0, 'pause: nothing in the window, DPS now 0')
  -- hits again after the pause: DPS now rises by the window, it does not jump to the last hit
  M.record(cfg, st2, T0 + 14000, 100, bolt, 'fire', false)
  local d = M.view(cfg, st2, T0 + 14000)
  eq(d.cur, 20, 'after the pause: one hit in the window is 100 / 5 s')
  eq(d.tot, 900, 'after the pause: total')
end

-- every source its own row; the shares add up to 100
do
  local function fresh() return M.newSession(9, 1, 'Training Dummy') end
  local c = M.configure({})
  local s9 = fresh()
  local srcs = {
    { k = 's:Witchfire Bolt', t = 's', n = 'Witchfire Bolt', i = 'exori flam' },
    { k = 's:Witchfire Bolt (over time)', t = 's', n = 'Witchfire Bolt (over time)', i = 'exori flam' },
    { k = 'd:Burning', t = 'd', n = 'Burning', i = 'burning' },
    { k = 'p:Pyre Oath', t = 'p', n = 'Pyre Oath', i = 'proc' },
    { k = 'm:Skeleton Minion', t = 'm', n = 'Skeleton Minion', i = 'summon' },
    { k = 'r:Sudden Death Rune', t = 'r', n = 'Sudden Death Rune', i = 'sd' },
    { k = 'w:Sword attacks', t = 'w', n = 'Sword attacks', i = 'sword' },
  }
  local amounts = { 3333, 1111, 777, 333, 222, 111, 55 }
  local elements = { 'fire', 'fire', 'fire', 'energy', 'death', 'holy', 'physical' }
  for i, src in ipairs(srcs) do M.record(c, s9, T0 + i, amounts[i], src, elements[i], false) end
  local view = M.view(c, s9, T0 + 3000)
  local rows = L.skillRows(view)
  eq(#rows, #srcs, 'a spell, its ticks, a dot, a proc, a minion, a rune and a weapon each get a row')
  local names = {}
  for _, r in ipairs(rows) do names[r.name] = true end
  for _, src in ipairs(srcs) do ok(names[src.n], 'a row for ' .. src.n) end
  local pctSum, fracSum, totalSum = 0, 0, 0
  for i, r in ipairs(rows) do
    pctSum = pctSum + r.pct
    fracSum = fracSum + r.frac
    totalSum = totalSum + r.total
    if i > 1 then ok(rows[i - 1].total >= r.total, 'sorted by damage at ' .. r.name) end
  end
  eq(pctSum, 100, 'the shares add up to 100')
  ok(math.abs(fracSum - 1) < 1e-9, 'the bars are shares of the total: they add up to the whole')
  eq(totalSum, view.tot, 'the rows add up to the total damage')
  eq(rows[1].frac, 3333 / view.tot, 'the first bar is its share of the total, not of the top row')
  local els = L.elementRows(view)
  eq(#els, 5, 'an element each: fire, energy, death, holy, physical')
  local es = 0
  for _, e in ipairs(els) do es = es + e.pct end
  eq(es, 100, 'the element shares add up to 100')
  -- more rows than the server sends: the rest is one Others row and the shares still add up
  local c2 = M.configure({ maxRowsSent = 3 })
  local many = L.skillRows(M.view(c2, s9, T0 + 3000))
  eq(#many, 4, 'three rows and Others')
  local ps = 0
  for _, r in ipairs(many) do ps = ps + r.pct end
  eq(ps, 100, 'with Others the shares add up to 100')
  -- the share rounding: thirds
  local sh = L.shares({ 1, 1, 1 })
  eq(sh[1] + sh[2] + sh[3], 100, 'thirds add up to 100')
  eq(table.concat(L.shares({ 0, 0 }), ','), '0,0', 'nothing: no share')
  eq(table.concat(L.shares({}), ','), '', 'no values')
  eq(L.shares({ 5 })[1], 100, 'one source is 100%')
  eq(table.concat(L.shares({ 50, 50 }), ','), '50,50', 'halves')
end

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('trainerdpslogic_test: OK (' .. checks .. ' checks)')
