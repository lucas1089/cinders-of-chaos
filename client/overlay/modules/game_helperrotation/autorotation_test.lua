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
    for _, n in ipairs(p.creatures) do
      eq(n, 1, c.name .. ' ' .. p.level .. ': every rule casts on one monster (O430)')
    end
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
-- (154, Eclipse of Ruin, is the Mystic line's level 1200 ultimate: a level 300 character does not know it)
local ULT = D.classes[5].ultimate
eq(ULT, 154, 'the Elementalist ultimate is Eclipse of Ruin')
local sel = A.select(5, 300, function(id) return id ~= ULT end)
local p300ids, _, p300moved = A.areaFirst(p300.spells, p300.creatures or {})
eq(table.concat(sel.ids, ','), table.concat(p300ids, ','), 'the preset, area spells first')
eq(sel.gap, p300moved and A.gap(sel.ids) or p300.gap, 'its gap')
eq(sel.changed, false, 'unchanged')
-- the ultimate takes no slot: with it castable the rotation is the same five, the ultimate first with one creature
do
  local withUlt = A.select(5, 300, function() return true end)
  eq(withUlt.ultimate, ULT, 'the ultimate is picked when it can be cast')
  eq(withUlt.ids[1], ULT, 'and comes first')
  eq(withUlt.creatures[1], 1, 'for one monster')
  eq(#withUlt.ids, #sel.ids + 1, 'on top of the same rotation')
  eq(table.concat(withUlt.ids, ',', 2), table.concat(sel.ids, ','), 'the five unchanged below it')
  eq(withUlt.gap, sel.gap, 'the gap of the five')
  local rules = A.rules(withUlt)
  eq(rules[1].spellId, ULT, 'the first shooter rule is the ultimate')
  eq(rules[1].creatures, 1, 'with one creature')
  eq(A.select(5, 300, function(id) return id ~= ULT end).ultimate, nil, 'not castable: none')
end
-- a spell the character cannot cast (not learned, a lower level) is replaced from an earlier preset
local missing = p300.spells[1]
local sel2 = A.select(5, 300, function(id) return id ~= missing and id ~= ULT end)
eq(sel2.changed, true, 'changed')
for _, id in ipairs(sel2.ids) do
  ok(id ~= missing, 'the missing spell is out')
end
ok(#sel2.ids <= 5 and #sel2.ids >= #p300.spells - 1, 'filled up to 5')
eq(sel2.gap, A.gap(sel2.ids), 'gap simulated again')
-- the monster count of every rule is 1 (O430: an area spell hits a lone target too, so it casts on a boss as well; the area
-- spells still go first, so a pack gets them before the single hits)
eq(#sel2.creatures, #sel2.ids, 'one monster count per spell')
for _, n in ipairs(sel2.creatures) do
  eq(n, 1, 'a monster count of 1')
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
        eq(sel.creatures[i], 1, c.name .. ': one monster is enough (O430)')
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
  local bare = A.select(1, 60, castAt(60), { topUp = false })
  eq(#bare.ids, #A.presetFor(1, 60).spells, 'level-up check: preset only, no top-up')
  local clicked = A.select(1, 60, castAt(60))
  ok(#clicked.ids > #bare.ids, 'a click tops up')
  -- a rotation the button wrote at 12, the player reaches 14 (new spells: Rime Bloom 200 and Arcane Ripple 85, O241, level 14 since O250)
  local sel18 = A.select(1, 12, castAt(12), { topUp = false })
  local written = A.rules(sel18)
  local marker = A.ruleIds(written)
  local sel20 = A.select(1, 14, castAt(14), { topUp = false })
  local action, newIds = A.levelUpAction(sel20, written, marker, {})
  eq(action, 'notice', 'option off: a notice, not a change')
  local named = {}
  for _, id in ipairs(newIds) do named[id] = true end
  ok(named[200], 'the new spell is named')
  action = A.levelUpAction(sel20, written, marker, { autoUpdate = true })
  eq(action, 'apply', 'option on: the button set may be updated')
  -- the player's own rules: never applied, even with the option on
  local own = { { type = 'spell', spellId = 19 }, { type = 'rune', itemId = 3155 } }
  action, newIds = A.levelUpAction(sel20, own, nil, { autoUpdate = true })
  eq(action, 'notice', 'own rules with the option on: still only a notice')
  -- ignored spells are not offered again
  action = A.levelUpAction(sel20, written, marker, { ignored = { [200] = true, [85] = true } })
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

-- a relog after a death: the class (0) or the spell table is not there yet, and nothing is cut from the saved lists
-- (owner 2026-10-27, "continua limpando a lista")
do
  local lists = function(sp) return sp.vocations[1] == 5 end
  local table_ = { [10] = { id = 10, vocations = { 5 } }, [99] = { id = 99, vocations = { 7 } } }
  local function classOkAt(vocation, known)
    return function(id) return A.classKeeps(known and table_[id] or nil, vocation, lists) end
  end
  local rules = { { type = 'spell', spellId = 10 }, { type = 'spell', spellId = 99 } }
  local slots = { { id = 10, percent = 45 }, { id = 99, percent = 65 } }
  local _, n = A.dropForeignRules(rules, classOkAt(0, true))
  eq(n, 0, 'class not told yet (0): no rule dropped')
  eq(A.dropForeignHeals(slots, classOkAt(0, true)), 0, 'class not told yet (0): no heal emptied')
  _, n = A.dropForeignRules(rules, classOkAt(5, false))
  eq(n, 0, 'spell table empty: no rule dropped')
  eq(A.dropForeignHeals(slots, classOkAt(5, false)), 0, 'spell table empty: no heal emptied')
  eq(slots[2].id, 99, 'the heal slot is still there')
  _, n = A.dropForeignRules(rules, classOkAt(5, true))
  eq(n, 1, 'class and table known: the foreign rule goes')
  eq(A.classKeeps({ id = 1, notOnServer = true }, 5, lists), false, 'a spell the server lacks goes with a class change')
end

-- the Thief line's attack spells of the O133 kit (owner 2026-10-24: Auto setup did not add Gutting Slash, Razor Rain,
-- Venom Spiral, Crescent Cut and Last Breath): the data knows each with its area rule, and a Thief who can cast
-- everything gets them, up to the five slots
do
  local rules = { [45] = false, [56] = true, [57] = false, [62] = true, [80] = false }
  for id, area in pairs(rules) do
    ok(D.spells[id], 'spell ' .. id .. ' is in the rotation data')
    eq(D.spells[id] and D.spells[id].area, area, 'spell ' .. id .. ': area rule')
  end
  eq(D.spells[45].words, 'kah vorn kaen', 'Gutting Slash words')
  for _, c in pairs(D.classes) do
    for _, id in ipairs(c.extras or {}) do ok(D.spells[id], c.name .. ': extra ' .. id .. ' known') end
  end
  local thief = D.classes[11]
  local thiefSpells = {}
  for _, p in ipairs(thief.presets) do for _, id in ipairs(p.spells) do thiefSpells[id] = true end end
  for _, id in ipairs(thief.extras or {}) do thiefSpells[id] = true end
  for _, id in ipairs({ 45, 56, 57, 62, 80 }) do
    ok(thiefSpells[id], 'the Thief reaches ' .. id)
  end
  local all = function(id) return thiefSpells[id] == true end
  local sel = A.select(11, 230, all)
  eq(#sel.ids, A.MAX_SPELLS, 'a level 230 Thief gets five spells')
  local got = {}
  for _, id in ipairs(sel.ids) do got[id] = true end
  -- O176 (owner 2026-10-24, shorter cooldowns for the strongest spells): the best set of the Thief line is five spells
  -- that fill every 2 s slot, Razor Rain among them; Last Breath (one target, 12 s) scores less than any of them
  -- (rotation_sim.py), so it is an extra: it joins the rotation as soon as a slot is free
  ok(got[56], 'Razor Rain is in the level 230 Thief rotation')
  -- (155, Eclipse Edge, is a level 500 quest spell: a level 230 Thief does not know it)
  local free = A.select(11, 230, function(id) return thiefSpells[id] and id ~= 57 and id ~= 62 and id ~= 236 and id ~= 45 and id ~= 155 end)
  local gotFree = {}
  for _, id in ipairs(free.ids) do gotFree[id] = true end
  ok(gotFree[80] and gotFree[56], 'Last Breath fills a free slot of the level 230 Thief rotation')
  -- level 100: Gutting Slash (unlocked at 100) is in the preset, the Thief is not left with three spells
  local at100 = A.select(11, 100, function(id) return thiefSpells[id] and (D.spells[id] and id ~= 56 and id ~= 57 and id ~= 62 and id ~= 80) end)
  local g100 = {}
  for _, id in ipairs(at100.ids) do g100[id] = true end
  ok(g100[45], 'Gutting Slash is in the level 100 Thief rotation')
  ok(#at100.ids >= 4, 'a level 100 Thief has four spells or more')
  -- the area spells sit above the single hits
  local seenSingle = false
  for _, id in ipairs(sel.ids) do
    if D.spells[id].area then ok(not seenSingle, 'area spells first') else seenSingle = true end
  end
end

-- ---------------------------------------------------------------- the rotation variants (O446)
-- the data: a block next to the default, which is untouched (the generator's digest holds the default rows; the shape here)
do
  local V = D.variants
  ok(V and V.classes and V.names, 'the data has a variants block')
  eq(table.concat(V.names, ','), table.concat(A.VARIANT_NAMES, ','), 'the names of the data are the names of the module')
  local MINES = { [3] = true, [7] = true, [15] = true, [11] = true, [12] = true, [13] = true } -- the classes that hold Seeker Mine
  local entries, withMines = 0, 0
  local lookup = A.spellTable()
  for vocId, byName in pairs(V.classes) do
    local c = D.classes[vocId]
    ok(c, 'variants of a known class ' .. tostring(vocId))
    for name, list in pairs(byName) do
      local known = false
      for _, n in ipairs(A.VARIANT_NAMES) do known = known or n == name end
      ok(known, c.name .. ': variant name ' .. name)
      if name == 'mines' then ok(MINES[vocId], c.name .. ' holds Seeker Mine') end
      local last = 0
      for i, e in ipairs(list) do
        entries = entries + 1
        local tag = c.name .. ' ' .. name .. ' ' .. e.level
        ok(e.level > last, tag .. ': by level')
        last = e.level
        ok(e.upTo == nil or e.upTo > e.level, tag .. ': upTo after level')
        if i < #list then ok(e.upTo and e.upTo <= list[i + 1].level, tag .. ': no overlap with the next') else ok(e.upTo == nil or e.upTo > e.level, tag .. ': last entry') end
        ok(#e.spells >= 1 and #e.spells <= A.MAX_SPELLS, tag .. ': 1-5 spells')
        eq(#e.creatures, #e.spells, tag .. ': a monster count per spell')
        local seen, mine, chi = {}, false, false
        for _, id in ipairs(e.spells) do
          ok(lookup[id], tag .. ': spell ' .. id .. ' has its numbers')
          ok(not seen[id], tag .. ': no spell twice')
          seen[id] = true
          mine = mine or id == 100
          chi = chi or (lookup[id] and lookup[id].chi)
        end
        for _, n in ipairs(e.creatures) do eq(n, 1, tag .. ': one monster') end
        eq(mine, name == 'mines', tag .. ': Seeker Mine in the mines variant and nowhere else')
        if mine then withMines = withMines + 1; ok(V.spells[100] and not D.spells[100], 'Seeker Mine is in the variant table, not the default one') end
        if not chi then eq(A.gap(e.spells), e.gap, tag .. ': Lua gap = generated gap') end
        ok(e.gap <= 2, tag .. ': a cast every 2 s')
        -- the owner's rules: at most +40% in the specialty, a visible price on the other count (single, pack)
        ok(e.one <= 40 and e.five <= 40, tag .. ': never above +40%')
        if name == 'single' then ok(e.one >= 5 and e.five <= -3, tag .. ': gain on one target, price on groups') end
        if name == 'pack' then ok(e.five >= 5 and e.one <= -3, tag .. ': gain on groups, price on one target') end
        eq(name == 'mines', e.moving ~= nil, tag .. ': the moving pack number only for the mines')
        -- never the default set of that level
        local p = A.presetFor(vocId, e.level)
        ok(p and table.concat(p.spells, ',') ~= table.concat(e.spells, ','), tag .. ': not the default set')
      end
    end
  end
  ok(entries > 100 and withMines > 5, 'the data holds variants: ' .. entries .. ' entries, ' .. withMines .. ' with mines')
  ok(not D.spells[99] and not D.spells[100], 'no snare in the default table')
end

-- the lookup: by class, level and name; the level edges follow level / upTo; a bad name or no entry is nothing
do
  local list = D.variants.classes[4].single -- Warrior
  local e = list[1]
  eq(A.variantFor(4, e.level, 'single'), e, 'the entry at its level')
  eq(A.variantFor(4, e.level - 1, 'single'), nil, 'nothing below it')
  eq(A.variantFor(4, e.upTo - 1, 'single'), e, 'the entry up to upTo')
  ok(A.variantFor(4, e.upTo, 'single') ~= e, 'not at upTo')
  eq(A.variantFor(4, 1000, 'single'), list[#list], 'the last entry has no end')
  eq(A.variantFor(4, 99999, 'single'), list[#list], 'at any level above')
  eq(A.variantFor(4, 500, 'default'), nil, 'the default is no variant')
  eq(A.variantFor(4, 500, 'mines'), nil, 'a Warrior has no mines')
  eq(A.variantFor(4, 500, 'fast'), nil, 'an unknown name')
  eq(A.variantFor(4, 500, nil), nil, 'no name')
  eq(A.variantFor(999, 500, 'single'), nil, 'an unknown class')
  eq(A.variantName('pack'), 'pack', 'a known name'); eq(A.variantName('x'), 'default', 'an unknown name: default')
  eq(A.variantName(nil), 'default', 'no name: default'); eq(A.variantName(5), 'default', 'a number: default')
  eq(table.concat(A.variantNames(4), ','), 'single,pack', 'the Warrior has single and pack')
  eq(table.concat(A.variantNames(11), ','), 'single,mines', 'the Thief has single and mines')
  -- O474: the Lich's default set moved with the dot rule (Soul Rot x1.5, Blightbrand x1.25), so a one target set now differs from it
  eq(table.concat(A.variantNames(21), ','), 'single', 'the Lich has one target (it had none before O474)')
  eq(#A.variantNames(999), 0, 'an unknown class has none')
  local at500 = A.variantsAt(4, 500)
  eq(#at500, 2, 'two variants of the Warrior at 500'); eq(at500[1].name, 'single', 'in the choice order'); eq(at500[2].name, 'pack', 'then pack')
end

-- select with a variant: the variant's set where there is one, the default everywhere else
do
  local all = function() return true end
  local noUlt = function(id) return id ~= D.classes[4].ultimate end
  local plain = A.select(4, 500, noUlt)
  local single = A.select(4, 500, noUlt, { variant = 'single' })
  local e = A.variantFor(4, 500, 'single')
  eq(single.variant, 'single', 'the variant that was applied'); eq(single.vs.one, e.one, 'its price: one target'); eq(single.vs.five, e.five, 'groups')
  local ids = A.areaFirst(e.spells, e.creatures)
  eq(table.concat(single.ids, ','), table.concat(ids, ','), 'the variant set, area spells first')
  eq(single.gap, A.gap(single.ids), 'its gap'); eq(single.changed, false, 'unchanged')
  ok(table.concat(single.ids, ',') ~= table.concat(plain.ids, ','), 'not the default set')
  eq(plain.variant, nil, 'no variant without a choice'); eq(plain.vs, nil, 'and no numbers')
  eq(single.level, plain.level, 'the level of the default preset')
  -- a level with no entry, an unknown name and the default name: the default set, byte for byte
  local d1 = A.select(4, 100, noUlt)
  eq(table.concat(A.select(4, 100, noUlt, { variant = 'single' }).ids, ','), table.concat(d1.ids, ','), 'no entry at level 100: the default')
  eq(A.select(4, 100, noUlt, { variant = 'single' }).variant, nil, 'and no variant applied')
  eq(table.concat(A.select(4, 500, noUlt, { variant = 'fast' }).ids, ','), table.concat(plain.ids, ','), 'an unknown name: the default')
  eq(table.concat(A.select(4, 500, noUlt, { variant = 'default' }).ids, ','), table.concat(plain.ids, ','), 'the default name: the default')
  eq(table.concat(A.select(4, 500, noUlt, { variant = 'mines' }).ids, ','), table.concat(plain.ids, ','), 'a variant the class lacks: the default')
  -- a spell the character cannot cast is replaced like in a preset, the rest of the variant stays
  local missing = e.spells[2]
  local cut = A.select(4, 500, function(id) return id ~= missing and noUlt(id) end, { variant = 'single' })
  eq(cut.changed, true, 'a spell missing: changed')
  for _, id in ipairs(cut.ids) do ok(id ~= missing, 'the missing spell is out') end
  eq(cut.gap, A.gap(cut.ids), 'the gap simulated again')
  -- no top-up: the variant alone (the level-up check)
  local bare = A.select(4, 500, noUlt, { variant = 'single', topUp = false })
  eq(#bare.ids, #e.spells, 'topUp false: the variant alone')
  -- the mines: Seeker Mine is in the list, known to the gap check and to areaFirst through the merged table
  local m = A.variantFor(11, 1000, 'mines')
  local thief = A.select(11, 1000, all, { variant = 'mines' })
  eq(thief.variant, 'mines', 'the Thief picks the mines variant'); eq(thief.vs.moving, m.moving, 'with the moving pack number')
  local has = false
  for _, id in ipairs(thief.ids) do has = has or id == 100 end
  ok(has, 'Seeker Mine is in the Thief rotation'); eq(thief.gap, A.gap(thief.ids), 'its gap, mine included')
  ok(A.spellTable()[100] and A.spellTable()[100].area, 'the merged table knows Seeker Mine as an area spell')
  eq(A.spellTable()[99], nil, 'and no Snare Trap')
  eq(A.spellTable()[D.classes[4].presets[1].spells[1]], D.spells[D.classes[4].presets[1].spells[1]], 'the main numbers win')
  -- a client with no variants block behaves as before
  local saved = D.variants
  D.variants = nil
  eq(A.variantFor(4, 500, 'single'), nil, 'no block: no variant'); eq(#A.variantNames(4), 0, 'no block: no names')
  eq(A.spellTable(), D.spells, 'no block: the table is the main one')
  eq(table.concat(A.select(4, 500, noUlt, { variant = 'single' }).ids, ','), table.concat(plain.ids, ','), 'no block: the default set')
  D.variants = saved
end

-- the texts: the price is the numbers of the entry
do
  eq(A.variantHint('single', { one = 9, five = -16 }), 'Bosses +9%, groups -16%', 'single: bosses first')
  eq(A.variantHint('pack', { one = -10, five = 8 }), 'Groups +8%, bosses -10%', 'pack: groups first')
  eq(A.variantHint('mines', { one = -5, five = 24 }), 'Mines: groups +24%, bosses -5%', 'mines')
  eq(A.variantHint('mines', nil), 'Not at your level: default set', 'no entry: says so')
  eq(A.variantHint('default', nil), 'Balanced: one target and groups', 'the default')
  eq(A.variantTitle('single'), 'One target', 'title'); eq(A.variantTitle('x'), 'Default', 'unknown: default')
  eq(A.variantLine({}), nil, 'no line without a variant'); eq(A.variantLine({ variant = 'pack' }), 'Rotation variant: Groups.', 'the result line')
  ok(A.variantTip('mines'):find('Seeker Mine'), 'the mines tip names the spell')
  for _, n in ipairs({ 'default', 'single', 'pack', 'mines' }) do ok(#A.variantHint(n, { one = 1, five = 1 }) <= 40, n .. ' hint fits one line') end
end

if fails > 0 then
  error(fails .. ' failure(s)')
end
print('autorotation_test: OK')
