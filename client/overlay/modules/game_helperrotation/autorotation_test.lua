-- luajit autorotation_test.lua && lua5.3 autorotation_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'autorotation_data.lua')
dofile(dir .. 'autorotation.lua')
local A = ChaosAutoRotation
local D = ChaosAutoRotationData
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end

-- every class of docs/CLASSES.md has presets; at the level bands every preset has at most 5 spells and from level 15
-- (the 2 s rule was removed on 2026-10-17; the generator's own checks are in tools/rotation_sim_test.py)
local classes = 0
for vocId, c in pairs(D.classes) do
  classes = classes + 1
  ok(#c.presets > 0, c.name .. ' has presets')
  local lastLevel = 0
  for _, p in ipairs(c.presets) do
    ok(p.level > lastLevel, c.name .. ' presets by level')
    lastLevel = p.level
    ok(#p.spells >= 1 and #p.spells <= A.MAX_SPELLS, c.name .. ' ' .. p.level .. ': 1-5 spells')
    eq(#p.creatures, #p.spells, c.name .. ' ' .. p.level .. ': a monster count per spell')
    local chi = false
    for _, id in ipairs(p.spells) do
      ok(D.spells[id], c.name .. ': spell ' .. id .. ' has its numbers')
      chi = chi or (D.spells[id] and D.spells[id].chi)
    end
    if not chi then
      -- the Lua gap check agrees with the generator's simulation
      eq(A.gap(p.spells), p.gap, c.name .. ' ' .. p.level .. ': Lua gap = generated gap')
    end
  end
  for _, band in ipairs({ 30, 60, 100, 300, 600, 1000 }) do
    local p = A.presetFor(vocId, band)
    ok(p, c.name .. ' has a preset at ' .. band)
    if p then
      ok(#p.spells <= 5, c.name .. ' ' .. band .. ': at most 5')
    end
  end
end
eq(classes, 21, 'the 21 classes')
-- the snares (Snare Trap 99, Seeker Mine 100) are cast by hand, never by a preset
ok(not D.spells[99] and not D.spells[100], 'no snare in a preset')

-- the gap check: one 2 s filler is enough; a 4 s spell alone leaves 4 s; a 4 s group cooldown leaves 4 s
local S = {
  [1] = { cooldown = 2000, groupCooldown = 2000, secondaryGroup = '', secondaryCooldown = 0, cast = 0 },
  [2] = { cooldown = 4000, groupCooldown = 2000, secondaryGroup = '', secondaryCooldown = 0, cast = 0 },
  [3] = { cooldown = 30000, groupCooldown = 4000, secondaryGroup = '', secondaryCooldown = 0, cast = 0 },
  [4] = { cooldown = 8000, groupCooldown = 2000, secondaryGroup = 'special', secondaryCooldown = 8000, cast = 0 },
  [5] = { cooldown = 8000, groupCooldown = 2000, secondaryGroup = 'special', secondaryCooldown = 8000, cast = 0 },
  [6] = { cooldown = 20000, groupCooldown = 2000, secondaryGroup = '', secondaryCooldown = 0, cast = 1500 },
}
eq(A.gap({ 1 }, S), 2, 'a 2 s filler')
eq(A.gap({ 2 }, S), 4, 'a 4 s spell alone')
eq(A.gap({ 2, 1 }, S), 2, 'the filler covers it')
eq(A.gap({ 3, 1 }, S), 4, 'a 4 s attack group lock')
eq(A.gap({ 4, 5 }, S), 8, 'two spells of one secondary group share it')
eq(A.gap({ 6, 1 }, S), 2, 'a 1.5 s cast fits in the group cooldown')

-- the Templar line: Radiant Smite (2 s since the rotation pass) fills every turn at level 100. At 300 the line has ten
-- attack spells (the attack kit, 2026-10-23); since the combat pass (O136) the best five keep no gap over 2 s: the
-- sim prefers a gap-free set within 90% of the best score (server/data/spells/README.md "Combat pass (O136)")
local templar = A.presetFor(23, 100)
eq(templar.gap, 2, 'Templar 100: 2 s')
ok(table.concat(templar.spells, ','):find('189'), 'Templar 100: Radiant Smite in it')
local templar300 = A.presetFor(23, 300)
eq(templar300.gap, 2, 'Templar 300: 2 s')
ok(#templar300.spells <= 5, 'Templar 300: at most 5 spells')

-- select: every spell castable gives the preset
local p300 = A.presetFor(5, 300) -- Elementalist
local sel = A.select(5, 300, function() return true end)
local p300ids, _, p300moved = A.areaFirst(p300.spells, p300.creatures or {})
eq(table.concat(sel.ids, ','), table.concat(p300ids, ','), 'the preset, area spells first')
eq(sel.gap, p300moved and A.gap(sel.ids) or p300.gap, 'its gap')
eq(sel.changed, false, 'unchanged')
-- a spell the character cannot cast (not learned, a lower level) is replaced from an earlier preset
local missing = p300.spells[1]
local sel2 = A.select(5, 300, function(id) return id ~= missing end)
eq(sel2.changed, true, 'changed')
for _, id in ipairs(sel2.ids) do
  ok(id ~= missing, 'the missing spell is out')
end
ok(#sel2.ids <= 5 and #sel2.ids >= #p300.spells - 1, 'filled up to 5')
eq(sel2.gap, A.gap(sel2.ids), 'gap simulated again')
-- the monster count of a changed set is the preset's own (an area spell waits for 2, the rest for 1)
eq(#sel2.creatures, #sel2.ids, 'one monster count per spell')
for _, n in ipairs(sel2.creatures) do
  ok(n == 1 or n == 2, 'a monster count of 1 or 2')
end
-- below the first preset, an unknown class
eq(A.select(4, 1), nil, 'level 1 Warrior: nothing yet')
eq(select(2, A.select(99, 300)), 'class', 'unknown class')
-- the preset follows the level: a level-up past a breakpoint changes it
local c = D.classes[5]
local a, b = c.presets[#c.presets - 1], c.presets[#c.presets]
eq(A.presetFor(5, b.level - 1), a, 'below the breakpoint')
eq(A.presetFor(5, b.level), b, 'at the breakpoint')

-- the helper's rules: priority order, the monster count, enabled
local rules = A.rules(sel, function(id) return 'S' .. id end, function(id) return 'w' .. id end)
eq(#rules, #sel.ids, 'one rule per spell')
eq(rules[1].type, 'spell', 'spell rules')
eq(rules[1].spellId, sel.ids[1], 'first spell first')
eq(rules[1].name, 'S' .. sel.ids[1], 'name')
eq(rules[1].words, 'w' .. sel.ids[1], 'words')
eq(rules[1].creatures, sel.creatures[1], 'creatures')
eq(rules[1].enabled, true, 'enabled')
eq(table.concat(A.ruleIds(rules), ','), table.concat(sel.ids, ','), 'rule ids')

-- custom: an empty list is not, the set the button wrote is not, anything else (or a rune) is
eq(A.isCustom({}, nil), false, 'empty')
eq(A.isCustom(rules, A.ruleIds(rules)), false, 'the auto set')
eq(A.isCustom(rules, nil), true, 'rules without a marker')
local edited = A.rules(sel)
table.remove(edited, 1)
eq(A.isCustom(edited, A.ruleIds(rules)), true, 'edited by the player')
eq(A.isCustom({ { type = 'rune', itemId = 3161 } }, {}), true, 'a rune rule')

-- heals: up to 3, the strongest at the lowest health, only castable ones
local heals = A.heals(4, 1000, function() return true end) -- Warrior
ok(#heals >= 1 and #heals <= 3, 'Warrior heals')
eq(heals[1].percent, 45, 'strongest at 45%')
if heals[2] then eq(heals[2].percent, 65, 'next at 65%') end
eq(#A.heals(4, 1000, function() return false end), 0, 'none castable')
eq(A.healingEmpty({ { id = 0 }, { id = 0 } }), true, 'empty healing tab')
eq(A.healingEmpty({ { id = 0 }, { id = 1 } }), false, 'filled healing tab')

-- a full rotation for every class: the preset's spells, then up to 5 with the other spells the character can cast
-- (a spell is castable from the first preset that lists it). The Mystic at level 8 used to get one rule.
local function firstLevel(c)
  local at = {}
  for _, p in ipairs(c.presets) do
    for _, id in ipairs(p.spells) do
      if not at[id] or p.level < at[id] then at[id] = p.level end
    end
  end
  return at
end
for vocId, c in pairs(D.classes) do
  local at = firstLevel(c)
  for _, level in ipairs({ 20, 60, 150, 400 }) do
    local castable = function(id) return at[id] ~= nil and at[id] <= level end
    local known = 0
    for _, l in pairs(at) do if l <= level then known = known + 1 end end
    local sel = A.select(vocId, level, castable)
    if sel then
      eq(#sel.ids, math.min(A.MAX_SPELLS, known), c.name .. ' level ' .. level .. ': full rotation')
      local seen = {}
      for i, id in ipairs(sel.ids) do
        ok(not seen[id], c.name .. ': no spell twice')
        seen[id] = true
        ok(castable(id), c.name .. ': only castable spells')
        ok(sel.creatures[i] == 1 or sel.creatures[i] == 2, c.name .. ': 1+ or 2+')
      end
      local preset = A.presetFor(vocId, level)
      local inSel = {}
      for _, id in ipairs(sel.ids) do inSel[id] = true end
      for _, id in ipairs(preset.spells) do ok(inSel[id], c.name .. ': the preset is in it') end
      local single = false
      for _, id in ipairs(sel.ids) do
        local area = D.spells[id] and D.spells[id].area
        ok(not (area and single), c.name .. ' level ' .. level .. ': area spells above single-target ones')
        if not area then single = true end
      end
    end
  end
end
do
  local m = D.classes[1]
  local at = firstLevel(m)
  local sel = A.select(1, 8, function(id) return at[id] ~= nil and at[id] <= 8 end)
  local first = sel.ids[1]
  ok(first == 169 or (D.spells[first] and D.spells[first].area), 'Mystic 8: an area spell, else Kindling Spark, first')
  eq(#sel.ids, 1, 'Mystic 8: Kindling Spark alone (the level 1 spells left with the 15-spell cap)')
end

-- area first: the area spells keep their order, then the single-target ones keep theirs; monster counts follow
do
  local SP = { [1] = { area = false }, [2] = { area = true }, [3] = { area = false }, [4] = { area = true } }
  local ids, cr, moved = A.areaFirst({ 1, 2, 3, 4 }, { 1, 2, 1, 3 }, SP)
  eq(table.concat(ids, ','), '2,4,1,3', 'area spells first, each group in order')
  eq(table.concat(cr, ','), '2,3,1,1', 'monster counts follow their spell')
  eq(moved, true, 'moved')
  local _, _, same = A.areaFirst({ 2, 1 }, { 2, 1 }, SP)
  eq(same, false, 'already in order')
end

-- "Add to my rules" keeps the player's rules on top, in their order, and adds no spell twice
do
  local user = { { type = 'spell', spellId = 200, name = 'mine', creatures = 3 }, { type = 'rune', itemId = 3155 },
    { type = 'spell', spellId = 19, name = 'mine too' } }
  local auto = A.rules({ ids = { 207, 200, 22 }, creatures = { 2, 2, 1 } })
  local merged, added = A.merge(user, auto)
  eq(#merged, 5, 'merged size')
  eq(added, 2, 'two new rules')
  eq(merged[1].name, 'mine', 'own rule first')
  eq(merged[1].creatures, 3, 'own rule unchanged')
  eq(merged[2].type, 'rune', 'own rune kept')
  eq(merged[3].spellId, 19, 'own order kept')
  eq(merged[4].spellId, 207, 'new rule appended')
  eq(merged[5].spellId, 22, 'spell already there skipped')
  merged[1].name = 'changed'
  eq(user[1].name, 'mine', 'the original list is a copy (undo)')
  local empty = A.merge(nil, auto)
  eq(#empty, 3, 'empty list: all generated rules')
  local copy = A.copyRules(user)
  eq(#copy, 3, 'copy size')
  ok(copy[1] ~= user[1], 'copied rule tables')
end

-- never a silent change on level-up (owner, 2026-10-16)
do
  local m = D.classes[1]
  local at = firstLevel(m)
  local castAt = function(level) return function(id) return at[id] ~= nil and at[id] <= level end end
  -- the level-up check keeps the preset: no top-up
  local bare = A.select(1, 150, castAt(150), { topUp = false })
  eq(#bare.ids, #A.presetFor(1, 150).spells, 'level-up check: preset only, no top-up')
  local clicked = A.select(1, 150, castAt(150))
  ok(#clicked.ids > #bare.ids, 'a click tops up')
  -- a rotation the button wrote at 18, the player reaches 20 (a new spell, 200)
  local sel18 = A.select(1, 18, castAt(18), { topUp = false })
  local written = A.rules(sel18)
  local marker = A.ruleIds(written)
  local sel20 = A.select(1, 20, castAt(20), { topUp = false })
  local action, newIds = A.levelUpAction(sel20, written, marker, {})
  eq(action, 'notice', 'option off: a notice, not a change')
  eq(newIds[1], 200, 'the new spell is named')
  action = A.levelUpAction(sel20, written, marker, { autoUpdate = true })
  eq(action, 'apply', 'option on: the button set may be updated')
  -- the player's own rules: never applied, even with the option on
  local own = { { type = 'spell', spellId = 19 }, { type = 'rune', itemId = 3155 } }
  action, newIds = A.levelUpAction(sel20, own, nil, { autoUpdate = true })
  eq(action, 'notice', 'own rules with the option on: still only a notice')
  -- ignored spells are not offered again
  action = A.levelUpAction(sel20, written, marker, { ignored = { [200] = true } })
  eq(action, 'none', 'an ignored spell is not offered again')
  -- nothing new: nothing at all
  action = A.levelUpAction(sel18, written, marker, { autoUpdate = true })
  eq(action, 'none', 'same level set: no change')
  eq((A.levelUpAction(nil, written, marker, {})), 'none', 'no rotation for the class')
  -- an empty list (a new character) is only offered spells, never filled
  eq((A.levelUpAction(sel20, {}, nil, {})), 'notice', 'empty list: a notice')
end

-- the message
eq(A.message({ ids = { 1, 2 }, gap = 2 }, function(id) return id == 1 and 'A' or 'B' end),
  'Rotation set: A > B (max gap 2.0 s)', 'message')

-- the "Auto-update my spells" box picks the label that fits beside Rename (pt-BR is longer)
local W = { full = 214, short = 118, box = 16 }
eq(A.autoBoxLabel(490, W), 'full', 'wide row: the full label')
eq(A.autoBoxLabel(214, W), 'full', 'exactly fits')
eq(A.autoBoxLabel(150, W), 'short', 'narrower: the short label')
eq(A.autoBoxLabel(40, W), 'none', 'the box alone')
eq(A.autoBoxLabel(10, W), 'hidden', 'no room at all: hidden, never over another widget')
eq(A.autoBoxLabel(nil, W), 'hidden', 'no measure yet')

-- a class change: rules and heals of spells the new class lacks go (base: the Vocation Change kept them)
do
  local classOk = function(id) return id == 10 or id == 11 end
  local rules = {
    { type = 'spell', spellId = 10, name = 'A' }, { type = 'spell', spellId = 99, name = 'old class' },
    { type = 'item', itemId = 3160, spellId = 0 }, { type = 'spell', spellId = 11, name = 'B' },
    { type = 'spell', spellId = 98, name = 'old class 2' },
  }
  local out, dropped = A.dropForeignRules(rules, classOk)
  eq(dropped, 2, 'two old-class rules dropped')
  eq(#out, 3, 'the rest stays')
  eq(out[1].spellId .. ',' .. out[2].type .. ',' .. out[3].spellId, '10,item,11', 'order and item rules kept')
  eq(#rules, 5, 'the source list is not changed')
  local _, none = A.dropForeignRules(out, classOk)
  eq(none, 0, 'a second pass drops nothing')
  eq(#A.dropForeignRules(nil, classOk), 0, 'no rules')
  local slots = { { id = 10, percent = 45 }, { id = 99, percent = 65 }, { id = 0, percent = 85 } }
  eq(A.dropForeignHeals(slots, classOk), 1, 'one heal slot emptied')
  eq(slots[1].id .. ',' .. slots[2].id .. ',' .. slots[2].percent, '10,0,65', 'the slot is emptied, its percent kept')
  eq(A.dropForeignHeals(slots, classOk), 0, 'idempotent')
end

if fails > 0 then
  error(fails .. ' failure(s)')
end
print('autorotation_test: OK')
