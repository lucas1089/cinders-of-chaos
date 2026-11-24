-- luajit ranklogic_test.lua && lua5.3 ranklogic_test.lua (CI runs it from the repo root, which also lets it hold the numbers
-- to the server's spell_ranks_config.lua and forms_data.lua to the pick rules)
local here = (arg and arg[0] and arg[0]:match('^(.*[/\\])') or '')
local L = dofile(here .. 'ranklogic.lua')
local n = 0
local function eq(a, b, m) n = n + 1 if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end
local function near(a, b, m) n = n + 1 if math.abs(a - b) > 1e-9 then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end end

eq(ChaosRankLogic, L, 'global')
eq(L.OPCODE, 168, 'opcode')

-- the state message
local st = L.cleanState({ on = true, v = 1, s = { { 2, 10, 1.5, 6 }, { 3, 20, 0, 0 }, { 9, 4, 0.2, 0.8 }, 'junk', { 'x' }, { 0, 1, 1, 1 }, { 7, 99, 5, 5 } } })
eq(st.on, true, 'on')
eq(st.ranks[2].rank, 10, 'rank') near(st.ranks[2].into, 1.5, 'into') near(st.ranks[2].cost, 6, 'cost')
eq(st.ranks[7].rank, 20, 'a rank above the top is held at 20') eq(st.ranks[7].cost, 0, 'no cost at the top')
eq(st.ranks[0], nil, 'id 0 dropped') eq(st.ranks[1], nil, 'junk dropped')
eq(L.cleanState(nil), nil, 'no state') eq(L.cleanState('x'), nil, 'junk state')
eq(L.cleanState({ on = false, s = {} }).on, false, 'off')
eq(L.cleanState({ s = { { 2, 3, 1, 1 } } }).on, false, 'no on flag: off')
eq(L.isOn(nil), false, 'no state: off') eq(L.isOn(L.cleanState({ on = false })), false, 'state off') eq(L.isOn(st), true, 'state on')
eq(L.rank(st, 2), 10, 'rank of 2') eq(L.rank(st, 55), 0, 'unknown spell rank 0') eq(L.rank(L.cleanState({ on = false, s = { { 2, 10, 1, 1 } } }), 2), 0, 'off: rank 0')

-- fractions
near(L.fraction(st.ranks[2]), 0.25, 'fraction') eq(L.rowPercent(st.ranks[2]), 25, 'row percent')
eq(L.rowPercent(st.ranks[3]), 100, 'top rank: full bar') near(L.spToGo(st.ranks[2]), 4.5, 'sp to go') eq(L.spToGo(st.ranks[3]), 0, 'none at the top')
eq(L.rowPercent({ rank = 1, into = 0.001, cost = 100 }), 1, 'a bit of progress shows') eq(L.rowPercent({ rank = 1, into = 0, cost = 5 }), 0, 'none')
eq(L.rowPercent(nil), 0, 'no entry')

-- the rank message
local ranks = {}
eq(L.applyRank(ranks, { 5, 3, 0.5, 2 }), 1, 'one row') eq(ranks[5].rank, 3, 'rank 5')
eq(L.applyRank(ranks, { { 5, 4, 0, 2 }, { 6, 1, 0, 1 } }), 2, 'a list') eq(ranks[5].rank, 4, 'updated') eq(ranks[6].rank, 1, 'added')
eq(L.applyRank(ranks, { s = { { 8, 2, 0, 1 } } }), 1, 's rows') eq(ranks[8].rank, 2, 'row 8')
eq(L.applyRank(ranks, 'x'), 0, 'junk') eq(L.applyRank(nil, { 1, 1, 1, 1 }), 0, 'no table')

-- the effects of a rank (design 1.5)
local t = L.totals(20, false)
near(t.power, 18, 'damage +18% at 20') near(t.cooldown, 10, 'cooldown -10% at 20') near(t.mana, 20, 'mana -20% at 20')
t = L.totals(20, true)
near(t.power, 12, 'heal +12% at 20') near(t.cooldown, 15, 'heal cooldown -15%') near(t.mana, 25, 'heal mana -25%')
near(L.totals(3, false).cooldown, 0, 'no cooldown cut below 4') near(L.totals(4, false).cooldown, 2, 'first step at 4')
near(L.gives(4, false).cooldown, 2, 'rank 4 gives -2%') near(L.gives(5, false).cooldown, 0, 'rank 5 none') near(L.gives(1, false).power, 0.9, 'rank 1 power')
near(L.gives(1, true).mana, 1.25, 'heal mana a rank') eq(L.cdSteps(20), 5, 'five steps')
near(L.totals(0, false).power, 0, 'rank 0 gives nothing')

-- forms_data.lua shapes
local data = {
  pick = { rank1 = 10, rank2 = 20, minPrice = 10000, perLevel = 150, freeSeconds = 1800 },
  kinds = { SPLIT = { text = 'Splits.' }, REND = { text = 'Rends.' }, ASCEND = { text = 'Ascends.' }, TWIN = { text = 'Twins.' } },
  spells = {
    [2] = { name = 'Gorehook', heal = false, element = 'physical', forms = { { { 'SPLIT', 'Splintering' }, { 'REND', 'Rending' } }, { { 'ASCEND:earth', 'Earth Ascension' }, { 'TWIN', 'Twin Cast' } } } },
    [3] = { name = 'Grand Mending', heal = true, forms = { { { 'SPLIT', 'A' }, { 'REND', 'B' } }, { { 'TWIN', 'C' }, { 'TWIN', 'D' } } } },
    [4] = { name = 'Broken', forms = { { { 'SPLIT', 'A' } } } },
  },
}
local f = L.formsFor(data, 2)
eq(f.heal, false, 'not a heal') eq(f.tiers[2][1].name, 'Earth Ascension', 'ascension name') eq(f.tiers[2][1].text, 'Ascends.', 'ASCEND:earth reads the ASCEND text')
eq(f.tiers[1][2].kind, 'REND', 'kind') eq(L.formsFor(data, 3).heal, true, 'heal')
eq(L.formsFor(data, 4), nil, 'a broken row') eq(L.formsFor(data, 99), nil, 'no forms') eq(L.formsFor(nil, 2), nil, 'no data')
eq(L.baseKind('ASCEND:holy'), 'ASCEND', 'base kind') eq(L.baseKind('SPLIT'), 'SPLIT', 'plain kind')
local rules = L.pickRules(data)
eq(rules.rank1, 10, 'rank1') eq(rules.freeSeconds, 1800, 'window') eq(L.pickRules(nil).perLevel, 150, 'defaults')

-- tiers
local s1 = L.tierState(rules, 9, 0, 0, 1) eq(s1.locked, true, 'rank 9: Form I locked') eq(s1.rankNeeded, 10, 'opens at 10')
s1 = L.tierState(rules, 10, 0, 0, 1) eq(s1.locked, false, 'rank 10: open') eq(s1.picked, 0, 'none picked')
local s2 = L.tierState(rules, 20, 0, 0, 2) eq(s2.locked, false, 'rank 20 open') eq(s2.needForm1, true, 'Form II needs Form I')
s2 = L.tierState(rules, 20, 2, 0, 2) eq(s2.needForm1, false, 'Form I picked')
s2 = L.tierState(rules, 15, 1, 0, 2) eq(s2.locked, true, 'rank 15: Form II locked') eq(s2.rankNeeded, 20, 'opens at 20')

-- price and quotes
eq(L.price(rules, 1000), 150000, 'level 1000 150,000 gold') eq(L.price(rules, 20), 10000, 'the floor') eq(L.price(rules, 0), 10000, 'level 0')
local function quote(tier, pick, rank, f1, f2, last, now) return L.quote(rules, 2, tier, pick, rank, f1, f2, 1000, last, now) end
eq(quote(1, 1, 9, 0, 0).kind, 'locked', 'locked') eq(quote(2, 1, 20, 0, 0).kind, 'form1', 'needs Form I')
eq(quote(1, 1, 10, 0, 0).kind, 'first', 'first pick is free') eq(quote(1, 1, 10, 1, 0).kind, 'same', 'same pick')
local q = quote(1, 2, 10, 1, 0, nil, 100) eq(q.kind, 'paid', 'a change is paid') eq(q.price, 150000, 'price')
q = quote(1, 2, 10, 1, 0, { spell = 2, tier = 1, at = 100 }, 100 + 1800) eq(q.kind, 'window', 'free window (edge)') eq(q.price, 0, 'free')
eq(quote(1, 2, 10, 1, 0, { spell = 2, tier = 1, at = 100 }, 100 + 1801).kind, 'paid', 'window over')
eq(quote(1, 2, 10, 1, 0, { spell = 3, tier = 1, at = 100 }, 101).kind, 'paid', 'only the last pick has a window: other spell')
eq(quote(1, 2, 10, 1, 0, { spell = 2, tier = 2, at = 100 }, 101).kind, 'paid', 'other tier')
eq(L.windowLeft(rules, 2, 1, { spell = 2, tier = 1, at = 100 }, 400), 1500, 'seconds left') eq(L.windowLeft(rules, 2, 1, nil, 400), nil, 'no last pick') eq(L.windowLeft(rules, 2, 1, { spell = 2, tier = 1, at = 100 }, 1900), 0, 'zero left still free')

-- forms message and pick answers
local picks = L.cleanForms({ v = 1, f = { { 2, 1, 2 }, { 3, 0, 0 }, 'junk', { 'x' }, { 9, 7, -1 } } })
eq(picks[2].f1, 1, 'f1') eq(picks[2].f2, 2, 'f2') eq(picks[9].f1, 2, 'a pick above 2 is held at 2') eq(picks[9].f2, 0, 'negative: 0') eq(picks[1], nil, 'junk')
eq(next(L.cleanForms(nil)), nil, 'no forms')
local res = L.cleanPick({ ok = true, why = 'paid', price = 150000, spell = 2, tier = 1, pick = 2, f1 = 2, f2 = 2 })
eq(res.ok, true, 'ok') eq(res.price, 150000, 'price') eq(res.f1, 2, 'f1')
L.applyPick(picks, res) eq(picks[2].f1, 2, 'applied')
L.applyPick(picks, L.cleanPick({ ok = true, why = 'first', spell = 5, tier = 2, pick = 1 })) eq(picks[5].f2, 1, 'without f1 / f2 the tier takes the pick') eq(picks[5].f1, 0, 'f1 stays')
L.applyPick(picks, L.cleanPick({ ok = false, why = 'gold', price = 100, spell = 6, tier = 1, pick = 1 })) eq(picks[6], nil, 'a refusal changes nothing')
eq(L.cleanPick('x'), nil, 'junk answer')
local code, good = L.whyCode({ ok = false, why = 'gold' }) eq(code, 'gold', 'gold') eq(good, false, 'refusal')
code, good = L.whyCode({ ok = true, why = 'window' }) eq(code, 'window', 'window') eq(good, true, 'accepted')
code = L.whyCode({ ok = false, why = 'surprise' }) eq(code, 'other', 'unknown reason')
code = L.whyCode({ ok = true, why = '' }) eq(code, 'first', 'ok without a reason')
for _, w in ipairs(L.WHY_FAIL) do local c, g = L.whyCode({ ok = false, why = w }) eq(c, w, 'known ' .. w) eq(g, false, 'fail ' .. w) end
for _, w in ipairs(L.WHY_OK) do local c, g = L.whyCode({ ok = true, why = w }) eq(c, w, 'known ' .. w) eq(g, true, 'ok ' .. w) end

-- the hub badge
local state = L.cleanState({ on = true, s = { { 2, 10, 0, 5 }, { 3, 9, 0, 5 }, { 99, 20, 0, 0 }, { 4, 20, 0, 0 } } })
eq(L.pickableCount(state, {}, data), 1, 'one spell with Form I open (3 is rank 9, 99 and 4 have no Forms)')
eq(L.pickableCount(state, { [2] = { f1 = 1, f2 = 0 } }, data), 0, 'Form I picked, rank 10: nothing to pick')
state.ranks[2].rank = 20
eq(L.pickableCount(state, { [2] = { f1 = 1, f2 = 0 } }, data), 1, 'Form II open')
eq(L.pickableCount(state, { [2] = { f1 = 1, f2 = 2 } }, data), 0, 'both picked')
eq(L.pickableCount(state, { [2] = { f1 = 0, f2 = 0 } }, data), 1, 'rank 20 with no pick: counts once')
eq(L.pickableCount(L.cleanState({ on = false, s = { { 2, 20, 0, 0 } } }), {}, data), 0, 'switch off: 0') eq(L.pickableCount(nil, {}, data), 0, 'no state: 0')
eq(L.isRankable(state, data, 2), true, 'rankable by forms') eq(L.isRankable(state, data, 4), true, 'rankable by rank') eq(L.isRankable(state, data, 77), false, 'not rankable')

-- from the repo root: the numbers equal the server's
local function load(path) local fn = loadfile(path) return fn and fn() or nil end
local cfg = load('server/data/scripts/chaos/spell_ranks_config.lua')
if cfg then
  eq(cfg.maxRank, L.MAX_RANK, 'max rank = server') eq(cfg.opcode, L.OPCODE, 'opcode = server')
  eq(cfg.effects.damage.power, L.EFFECTS.damage.power, 'damage power') eq(cfg.effects.damage.cooldownPerStep, L.EFFECTS.damage.cooldownPerStep, 'damage cd')
  eq(cfg.effects.damage.mana, L.EFFECTS.damage.mana, 'damage mana') eq(cfg.effects.heal.power, L.EFFECTS.heal.power, 'heal power')
  eq(cfg.effects.heal.cooldownPerStep, L.EFFECTS.heal.cooldownPerStep, 'heal cd') eq(cfg.effects.heal.mana, L.EFFECTS.heal.mana, 'heal mana')
  eq(table.concat(cfg.effects.cdRanks, ','), table.concat(L.CD_RANKS, ','), 'cd ranks')
  for k, v in pairs(L.DEFAULT_PICK) do eq(cfg.forms[k], v, 'default pick ' .. k) end
  local fd = loadfile('client/overlay/modules/game_spellranks/forms_data.lua')
  if fd then
    fd()
    local r = L.pickRules(ChaosFormsData)
    for k, v in pairs(L.DEFAULT_PICK) do eq(r[k], v, 'forms_data pick ' .. k) end
    -- every spell of the data reads back with two tiers of two Forms, each with a name and a sentence
    local c = 0
    for id in pairs(ChaosFormsData.spells) do
      local ff = L.formsFor(ChaosFormsData, id)
      eq(ff ~= nil, true, 'forms of ' .. id)
      for tier = 1, 2 do
        for pick = 1, 2 do
          eq(ff.tiers[tier][pick].text ~= '', true, 'sentence of ' .. id .. '/' .. tier .. '/' .. pick)
          eq(ff.tiers[tier][pick].name ~= '', true, 'name of ' .. id)
        end
      end
      c = c + 1
    end
    eq(c > 80, true, 'the data holds the spells')
  end
end

-- O752: the spell path milestones of the state (server spell_milestones_core.lua M.wire)
do
  local wire = { f1 = 300, f2 = { { 500, 1050 }, { 1200, 1650 }, { 0, 2400 } }, aw = { { 500, 0 }, { 1200, 2100 }, { 0, 2500 } },
    sl = { 1800, 1950, 2250 }, nx = { l = 1500, k = 'form1', n = 'Doomtide', c = 2 } }
  local s2 = L.cleanState({ on = true, s = { { 7, 20, 0, 0 }, { 8, 20, 0, 0 } }, ms = wire })
  local ms = s2.ms
  eq(ms.f1, 300, 'ms: Form I add')
  eq(ms.f2[3].below, nil, 'ms: the last row takes the rest')
  eq(L.formGate(ms, 1, 100), 400, 'Form I gate')
  eq(L.formGate(ms, 2, 100), 1050, 'Form II gate of an early spell')
  eq(L.formGate(ms, 2, 500), 1650, 'of a line spell')
  eq(L.formGate(ms, 2, 1200), 2400, 'of an ultimate')
  eq(L.formGate(nil, 2, 1200), 0, 'no ms: no gate')
  eq(L.awakenGate(ms, 100), 0, 'an early spell awakens by its slot')
  eq(L.awakenGate(ms, 1200), 2500, 'an ultimate at the cap')
  eq(L.slotGate(ms, 2), 1950, 'slot 2') eq(L.slotGate(ms, 9), 0, 'no slot 9')
  eq(L.cleanMilestones('x'), nil, 'junk ms')
  eq(L.cleanMilestones({ nx = { l = 10, k = 'nonsense' } }).nx, nil, 'an unknown kind is dropped')
  eq(L.cleanState({ on = true }).ms, nil, 'a state with no ms')
  -- the tier under its level
  local rules = L.pickRules(nil)
  local t1 = L.tierState(rules, 20, 0, 0, 1, 400, 399)
  eq(t1.levelLocked, true, 'Form I under its level') eq(t1.levelNeeded, 400, 'its level')
  eq(L.tierState(rules, 20, 1, 0, 1, 400, 10).levelLocked, false, 'a pick already made is never level locked')
  eq(L.tierState(rules, 20, 0, 0, 1, 400, 400).levelLocked, false, 'at the level it opens')
  eq(L.tierState(rules, 20, 0, 0, 1).levelLocked, false, 'no gate given')
  local q = L.quote(rules, 7, 1, 1, 20, 0, 0, 399, nil, 0, 400)
  eq(q.kind, 'level', 'the quote under the level') eq(q.level, 400, 'names it')
  eq(L.quote(rules, 7, 1, 1, 5, 0, 0, 399, nil, 0, 400).kind, 'locked', 'the rank first')
  eq(L.quote(rules, 7, 1, 1, 20, 0, 0, 400, nil, 0, 400).kind, 'first', 'at the level: the first pick')
  -- the badge does not count a tier under its level
  local data = { spells = {}, kinds = {} }
  for _, id in ipairs({ 7, 8 }) do
    data.spells[id] = { forms = { { { 'SPLIT', 'a' }, { 'SPLIT', 'b' } }, { { 'SPLIT', 'c' }, { 'SPLIT', 'd' } } } }
  end
  local learn = { [7] = 100, [8] = 1200 }
  eq(L.pickableCount(s2, {}, data), 2, 'no levels known: both count')
  eq(L.pickableCount(s2, {}, data, 1000, function(id) return learn[id] end), 1, 'the ultimate waits for level 1500')
  eq(L.pickableCount(s2, {}, data, 1500, function(id) return learn[id] end), 2, 'at 1500 both')
  -- the next milestone
  local tr = function(f, ...) return string.format(f, ...) end
  local short, long = L.milestoneText(ms, 1400, tr)
  eq(short, 'Next unlock: level 1500', 'short text')
  eq(long, 'At level 1500: Form I of Doomtide opens and 1 more.', 'long text')
  eq(L.milestoneText(ms, 1500, tr), nil, 'past it: nothing until the next state')
  eq(L.milestoneText(nil, 1, tr), nil, 'no ms')
  for _, k in ipairs(L.MILESTONE_KINDS) do
    local m = L.cleanMilestones({ nx = { l = 10, k = k, n = 'X', s = 2 } })
    local a, b = L.milestoneText(m, 1, tr)
    eq(type(a) == 'string' and type(b) == 'string', true, 'a text for ' .. k)
  end
  eq(L.cleanPick({ ok = false, why = 'level', need = 1050 }).need, 1050, 'the pick answer keeps the level')
end

print('ranklogic_test: ' .. n .. ' checks OK')
