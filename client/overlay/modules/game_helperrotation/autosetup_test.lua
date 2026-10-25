-- luajit autosetup_test.lua && lua5.3 autosetup_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'autorotation_data.lua')
dofile(dir .. 'autorotation.lua')
dofile(dir .. 'autosetup.lua')
dofile(dir .. '../game_chaosspells/spelldata.lua')
dofile(dir .. '../game_helpersupport/supportspells.lua')
local A, S = ChaosAutoRotation, ChaosAutoSetup
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- spells: the Chaos spells from the generated client data; the stock hastes as the server lists them after
-- add_vocations.py (Haste: every line from level 14; Strong Haste: the Mystic line from level 20)
local chaos = {}
for _, s in ipairs(ChaosSpellData) do chaos[s.id] = s end
local stock = {
  [6] = { level = 14, vocations = { 4, 8, 14, 3, 7, 15, 1, 5, 10, 11, 12, 13, 17, 18, 19, 20, 21, 22, 23, 24, 25 } },
  [39] = { level = 20, vocations = { 1, 5, 10 } },
}
local function canCastFor(voc, level)
  return function(id)
    local s = chaos[id] or stock[id]
    if not s then
      -- heal and rotation spells of the class data: castable at their level
      return true
    end
    local listed = false
    for _, v in ipairs(s.vocations) do if v == voc then listed = true end end
    return listed and s.level <= level
  end
end
local function planFor(voc, level, carried, held)
  local canCast = canCastFor(voc, level)
  local set = {}
  for _, id in ipairs(carried or {}) do set[id] = true end
  return S.plan({ vocId = voc, level = level, canCast = canCast, has = function(id) return set[id] == true end, held = held,
    heals = A.heals(voc, level, canCast), rotation = A.select(voc, level, canCast) })
end
local function timerIds(plan)
  local out = {}
  for _, r in ipairs(plan.timers) do out[#out + 1] = r.chaosAutoSetup end
  table.sort(out)
  return table.concat(out, ',')
end
local ALL_POTIONS = { 23375, 23374, 7643, 7642, 239, 236, 266, 7876, 23373, 238, 237, 268 }

-- every class of docs/CLASSES.md has a line, and every line a plan at levels 1, 50, 100 and 300
local names = { [4] = 'Warrior', [8] = 'Juggernaut', [14] = 'Berserker', [3] = 'Ranger', [7] = 'Deadeye',
  [15] = 'Beastmaster', [1] = 'Mystic', [5] = 'Elementalist', [10] = 'Illusionist', [11] = 'Thief', [12] = 'Ninja',
  [13] = 'Samurai', [17] = 'Monk', [18] = 'Shadowfist', [19] = 'Iron Sage', [20] = 'Necromancer', [21] = 'Lich',
  [22] = 'Bone Lord', [23] = 'Templar', [24] = 'Inquisitor', [25] = 'Sentinel' }
for voc, name in pairs(names) do
  ok(S.lineOf(voc), name .. ' has a line')
  for _, level in ipairs({ 1, 50, 100, 300 }) do
    local p = planFor(voc, level, ALL_POTIONS)
    eq(#p.healing.potions, 2, name .. ' ' .. level .. ': a health and a mana potion')
    eq(p.tools.autoEatFood, true, name .. ': eat food on')
    -- every planned spell is one the character can cast
    local canCast = canCastFor(voc, level)
    for _, r in ipairs(p.timers) do ok(canCast(r.chaosAutoSetup), name .. ' ' .. level .. ': timer spell castable') end
    if p.tools.haste then ok(canCast(p.tools.haste), name .. ': haste castable') end
    for _, h in ipairs(p.healing.spells) do
      ok(h.percent >= 50 and h.percent <= 80, name .. ': heal threshold in 50-80')
    end
    -- every potion it gets may be drunk by the class at the level
    local line = S.lineOf(voc)
    for kind, list in pairs(S.POTIONS) do
      local got = kind == 'health' and p.healing.potions[1].id or p.healing.potions[2].id
      local allowed = got == S.EVERFULL[kind]
      for _, pot in ipairs(list) do
        if pot.id == got and S.canDrink(pot, line, level) then allowed = true end
      end
      ok(allowed, name .. ' ' .. level .. ': ' .. kind .. ' potion ' .. got .. ' allowed')
    end
  end
end

-- potions: the best the character carries (every class drinks every potion, owner 2026-10-24), else the Everfull look
eq(planFor(4, 300, ALL_POTIONS).healing.potions[1].id, 23375, 'Warrior 300: supreme health')
eq(planFor(4, 300, ALL_POTIONS).healing.potions[2].id, 23373, 'Warrior 300: ultimate mana')
eq(planFor(4, 300, ALL_POTIONS).healing.potions[2].percent, 30, 'Warrior: mana potion at 30 %')
eq(planFor(4, 100, ALL_POTIONS).healing.potions[1].id, 7642, 'Warrior 100: great spirit')
eq(planFor(4, 100, { 236 }).healing.potions[1].id, 236, 'Warrior carrying strong health only')
eq(planFor(4, 100, {}).healing.potions[1].id, 266, 'nothing carried: the Everfull health potion')
eq(planFor(4, 100, {}).healing.potions[1].percent, 50, 'health potion at 50 %')
eq(planFor(3, 150, ALL_POTIONS).healing.potions[1].id, 23374, 'Ranger 150: ultimate spirit')
eq(planFor(3, 150, ALL_POTIONS).healing.potions[2].id, 23373, 'Ranger 150: ultimate mana')
eq(planFor(1, 150, ALL_POTIONS).healing.potions[2].id, 23373, 'Mystic 150: ultimate mana')
eq(planFor(1, 150, ALL_POTIONS).healing.potions[2].percent, 40, 'Mystic: mana potion at 40 %')
eq(planFor(1, 250, ALL_POTIONS).healing.potions[1].id, 23375, 'Mystic 250: supreme health (no class limit)')
eq(planFor(20, 90, ALL_POTIONS).healing.potions[2].id, 238, 'Necromancer 90: great mana')
eq(planFor(20, 90, ALL_POTIONS).healing.potions[2].percent, 40, 'Necromancer: a caster')
eq(planFor(12, 90, ALL_POTIONS).healing.potions[1].id, 7642, 'Ninja 90: great spirit')
eq(planFor(18, 60, ALL_POTIONS).healing.potions[1].id, 236, 'Monk line 60: strong health')
eq(planFor(23, 250, ALL_POTIONS).healing.potions[1].id, 23375, 'Templar 250: supreme health')
eq(planFor(23, 250, ALL_POTIONS).healing.potions[2].id, 23373, 'Templar 250: ultimate mana')
eq(planFor(5, 49, ALL_POTIONS).healing.potions[2].id, 268, 'level 49: no strong potions yet')

-- haste: Strong Haste for the Mystic line, Haste for the others from level 14
eq(planFor(1, 30).tools.haste, 6, 'Mystic: Haste (Galeborne Stride is retired)')
eq(planFor(4, 30).tools.haste, 6, 'Warrior: haste')
eq(planFor(4, 10).tools.haste, nil, 'level 10: no haste yet')

-- timers: the class buffs it can cast
eq(timerIds(planFor(4, 120)), '222', 'Warrior 120: Red Frenzy')
eq(timerIds(planFor(4, 90)), '', 'Warrior 90: nothing yet')
eq(timerIds(planFor(14, 150)), '222', 'Berserker: Red Frenzy, never Bloodrage (costs health)')
eq(timerIds(planFor(3, 150)), '217,233', 'Ranger 150: Lightward and Banner Call')
eq(timerIds(planFor(1, 70)), '209,233', 'Mystic 70: Ironbark Hide and Banner Call')
eq(timerIds(planFor(5, 70)), '233', 'Elementalist: no Ironbark Hide (Mystic and Illusionist only)')
eq(timerIds(planFor(11, 70)), '233,239', 'Thief 70: Poison Blades and Banner Call')
eq(timerIds(planFor(13, 160)), '233,239,245', 'Samurai 160: and Bushido Focus')
eq(timerIds(planFor(12, 160)), '233,239', 'Ninja: no Bushido Focus')
eq(timerIds(planFor(19, 160)), '72,233', 'Iron Sage 160: Mantra of Stone')
eq(timerIds(planFor(17, 160)), '233', 'Monk: Banner Call')
eq(timerIds(planFor(22, 160)), '233', 'Bone Lord: Banner Call only (no minion buffs)')
eq(timerIds(planFor(24, 160)), '233,250', 'Inquisitor 160: Zealotry')
eq(timerIds(planFor(25, 160)), '233', 'Sentinel: no Aegis of Faith (needs a shield)')
local r = planFor(4, 120).timers[1]
eq(r.cooldown, 41, 'timer waits one second more than the cooldown')
eq(r.unit, 'sec', 'in seconds')
eq(r.inPz, false, 'not in protection zones')
eq(r.targetingMonster, true, 'only while attacking a monster')

-- heals: the class heals, the strongest at the lowest health
local hs = S.healSlots({ { id = 102 }, { id = 1 }, { id = 123 } })
eq(hs[1].percent .. '/' .. hs[2].percent .. '/' .. hs[3].percent, '50/65/80', 'three heals')
eq(S.healSlots({ { id = 1 } })[1].percent, 80, 'one heal at 80 %')
eq(#planFor(4, 300).healing.spells > 0, true, 'Warrior has heals')
eq(planFor(4, 300).rotation ~= nil, true, 'Warrior 300 gets a rotation')

-- the player's own settings
local plan = planFor(4, 120)
eq(#S.ownTabs({ spells = { { id = 0 } }, potions = {}, haste = 0, rotationCustom = false, timers = {} }, plan), 0,
  'nothing of the player: no question')
local tabs = S.ownTabs({ spells = { { id = 1 } }, potions = {}, haste = 39, rotationCustom = true,
  timers = { { value = 'utani hur' } } }, plan)
eq(table.concat(tabs, ','), 'healing,tools,shooter,timers', 'own settings in every tab')
eq(#S.ownTabs({ timers = { { value = 'vyr ira cruor', chaosAutoSetup = 222 } } }, plan), 0,
  'its own earlier timer rules are not the player\'s')
eq(#S.ownTabs({ haste = 6 }, plan), 0, 'the same haste is not a change')

-- merging
local cur = { { id = 1, percent = 70 }, { id = 0, percent = 80 }, { id = 0, percent = 80 } }
local planned = { { id = 102, percent = 50 }, { id = 1, percent = 80 } }
local m = S.mergeSlots(cur, planned, 'add')
eq(m[1].id .. ':' .. m[1].percent, '1:70', 'add: the player\'s slot stays')
eq(m[2].id, 102, 'add: the plan fills an empty slot')
eq(m[3].id, 0, 'add: a heal already there is not added twice')
m = S.mergeSlots(cur, planned, 'replace')
eq(m[1].id .. ':' .. m[1].percent, '102:50', 'replace: the plan')
eq(m[3].id, 0, 'replace: the rest emptied')
local full = { { id = 5 }, { id = 6 }, { id = 7 } }
eq(S.mergeSlots(full, planned, 'add')[3].id, 7, 'add: no room, nothing lost')
local timers = { { type = 'words', value = 'utani hur' }, { type = 'words', value = 'tor vas vant', chaosAutoSetup = 233 } }
local t = S.mergeTimers(timers, planFor(3, 150).timers, 'add')
eq(#t, 3, 'add: the player\'s rule plus the two buffs (the old Auto setup rule replaced)')
eq(t[1].value, 'utani hur', 'add: the player\'s rule first')
t = S.mergeTimers({ { type = 'words', value = 'TOR SOL GHAR' } }, planFor(3, 150).timers, 'add')
eq(#t, 2, 'add: a buff the player already times is not added twice')
eq(#S.mergeTimers(timers, planFor(3, 150).timers, 'replace'), 2, 'replace: only the plan')
eq(S.mergeHaste(6, 39, 'add'), 6, 'add: the player\'s haste stays')
eq(S.mergeHaste(6, 39, 'replace'), 39, 'replace: the plan\'s haste')
eq(S.mergeHaste(0, nil, 'replace'), 0, 'no haste to cast: unchanged')

-- the Support spells section (game_helpersupport): the plan takes the timers and the support rows from the spell data
local entries = {}
for _, s in ipairs(ChaosSpellData) do
  entries[#entries + 1] = { id = s.id, name = s.name, words = s.words, level = s.level, mana = s.mana,
    group = { [s.group] = s.groupCooldown }, exhaustion = s.cooldown, needTarget = s.needTarget, parameter = false,
    vocations = s.vocations }
end
local function planWithSupport(voc, level)
  local canCast = canCastFor(voc, level)
  return S.plan({ vocId = voc, level = level, canCast = canCast, has = function() return false end,
    heals = A.heals(voc, level, canCast), rotation = A.select(voc, level, canCast),
    support = ChaosHelperSupport.autoPlan(entries, canCast) })
end
local sp = planWithSupport(13, 200)           -- Samurai
local more, total = 0, 0
for _, voc in ipairs({ 4, 8, 14, 3, 7, 15, 1, 5, 10, 11, 12, 13, 17, 18, 19, 20, 21, 22, 23, 24, 25 }) do
  local new, old = planWithSupport(voc, 300), planFor(voc, 300)
  ok(#new.timers >= #old.timers, 'vocation ' .. voc .. ': no fewer timer rules than before')
  ok(#new.timers <= ChaosHelperSupport.TIMER_MAX, 'vocation ' .. voc .. ': within the timer limit')
  if #new.timers > #old.timers then more = more + 1 end
  total = total + #new.support
end
ok(more >= 5, 'at least five classes get more timer rules than the hand-written list gave (' .. more .. ')')
ok(total >= 21, 'every class has a support row or more (' .. total .. ')')
eq(sp.timers[1].unit, 'sec', 'timer rule in seconds')
eq(sp.timers[1].targetingMonster, true, 'timer rule: only while attacking a monster')
eq(sp.timers[1].inNonPz, true, 'timer rule: outside protection zones')
ok(sp.timers[1].chaosAutoSetup, 'timer rule: marked as Auto setup\'s')
ok(#sp.support >= 1, 'the plan lists support spells for the new section')
eq(planFor(13, 200).support and #planFor(13, 200).support or 0, 0, 'without the module\'s plan: no support rows')
eq(#S.ownTabs({ support = {} }, sp), 0, 'an empty support section is nobody\'s')
eq(#S.ownTabs({ support = { { id = sp.support[1] } } }, sp), 0, 'a row of the plan is not the player\'s own')
local own = S.ownTabs({ support = { { id = 12345 } } }, sp)
eq(own[1], 'support', 'a row of the player\'s own is asked about')

-- targeting (owner 2026-10-22): Auto Target and the shooter on (the protection zone pause is the helper's own rule);
-- written into the helper's config and put back by Undo
local tp = planFor(13, 200).targeting
eq(tp.autoTargetEnabled, true, 'targeting: Auto Target on')
eq(tp.magicShooterEnabled, true, 'targeting: Enable Shooter on')
tp.autoTargetEnabled = false
eq(S.targeting().autoTargetEnabled, true, 'targeting: each plan has its own copy')
-- the helper's defaults: both systems off
local cfg = { autoTargetEnabled = false, magicShooterEnabled = false, autoEatFood = true }
local before = S.targetingOf(cfg)
S.applyTargeting(cfg, planFor(13, 200).targeting)
eq(cfg.autoTargetEnabled, true, 'applied: Auto Target on')
eq(cfg.magicShooterEnabled, true, 'applied: shooter on')
eq(cfg.autoEatFood, true, 'applied: other fields untouched')
S.applyTargeting(cfg, before)
eq(cfg.autoTargetEnabled, false, 'undo: Auto Target back off')
eq(cfg.magicShooterEnabled, false, 'undo: shooter back off')
eq(S.applyTargeting(nil, before), nil, 'no config: nothing written')


-- the autosetup potion table and the helper's potion list (helper_potions.lua) say the same: ids, levels, class lines
dofile(dir .. '../game_helper/helper_potions.lua')
do
  local P = ChaosHelperPotions
  local seen = 0
  for _, list in pairs(S.POTIONS) do
    for _, e in ipairs(list) do
      seen = seen + 1
      local p = P.info(e.id)
      ok(p, 'autosetup potion ' .. e.id .. ' is in the helper list')
      if p then
        eq(e.level, p.level, 'level of ' .. e.id)
        eq(e.lines, nil, 'no class limit on ' .. e.id)
      end
    end
  end
  eq(seen, #P.LIST, 'autosetup lists every potion once')
end


-- the Everfull the server says the character carries counts as carried (O246): the best tier it holds, at its level
local function heldOf(h, m)
  local v = {}
  if h then v.health = { look = h[1], tier = h[2], level = h[3], line = h[4] or 'health', ready = true } end
  if m then v.mana = { look = m[1], tier = m[2], level = m[3], line = 'mana', ready = true } end
  return v
end
eq(planFor(4, 100, {}, heldOf({ 239, 2, 80 }, { 238, 2, 80 })).healing.potions[1].id, 239, 'Everfull great health, nothing else: it is chosen')
eq(planFor(4, 100, {}, heldOf({ 239, 2, 80 }, { 238, 2, 80 })).healing.potions[2].id, 238, 'Everfull great mana')
eq(planFor(4, 300, {}, heldOf({ 23375, 4, 200 }, { 23373, 3, 130 })).healing.potions[1].id, 23375, 'Everfull supreme health at 300')
eq(planFor(4, 300, {}, heldOf({ 23375, 4, 200 }, { 23373, 3, 130 })).healing.potions[2].id, 23373, 'Everfull ultimate mana at 300')
eq(planFor(4, 300, { 23375 }, heldOf({ 239, 2, 80 })).healing.potions[1].id, 23375, 'a stock supreme carried beats a great Everfull')
eq(planFor(4, 100, { 236 }, heldOf({ 239, 2, 80 })).healing.potions[1].id, 239, 'the great Everfull beats a stock strong potion')
eq(planFor(4, 100, {}, heldOf({ 7642, 2, 80, 'spirit' })).healing.potions[1].id, 7642, 'a spirit Everfull is the health potion (as the stock spirit potions are)')
eq(planFor(4, 100, {}, heldOf({ 266, 1, 0 }, { 268, 1, 0 })).healing.potions[1].id, 266, 'tier 1: its look')
eq(planFor(4, 70, {}, heldOf({ 239, 2, 80 })).healing.potions[1].id, 266, 'below the level of the Everfull the fallback look is kept')
eq(planFor(4, 100, {}, nil).healing.potions[2].id, 268, 'no view: the mana fallback')

if fails > 0 then error(fails .. ' failure(s)') end
print('autosetup_test: OK')
