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
-- up never 2 s without one (the generator's own check, tools/rotation_sim_test.py, runs the full simulation)
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
    -- from level 15 up never 2 s without a cast (below 15 exempt)
    if p.level >= 15 then
      ok(p.gap <= A.GAP_LIMIT, c.name .. ' ' .. p.level .. ': gap ' .. p.gap .. ' <= 2.0 s')
    end
  end
  for _, band in ipairs({ 30, 60, 100, 300, 600, 1000 }) do
    local p = A.presetFor(vocId, band)
    ok(p, c.name .. ' has a preset at ' .. band)
    if p then
      ok(#p.spells <= 5, c.name .. ' ' .. band .. ': at most 5')
      ok(p.gap <= A.GAP_LIMIT, c.name .. ' ' .. band .. ': gap ' .. p.gap .. ' <= 2.0 s')
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

-- the Templar line: Radiant Smite (2 s since the rotation pass) fills every turn
local templar = A.presetFor(23, 300)
eq(templar.gap, 2, 'Templar 300: 2 s')
ok(table.concat(templar.spells, ','):find('189'), 'Templar 300: Radiant Smite in it')

-- select: every spell castable gives the preset
local p300 = A.presetFor(5, 300) -- Elementalist
local sel = A.select(5, 300, function() return true end)
eq(table.concat(sel.ids, ','), table.concat(p300.spells, ','), 'the preset as it is')
eq(sel.gap, p300.gap, 'its gap')
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
for _, n in ipairs(sel2.creatures) do
  eq(n, 1, 'a changed set waits for no crowd')
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

-- the message
eq(A.message({ ids = { 1, 2 }, gap = 2 }, function(id) return id == 1 and 'A' or 'B' end),
  'Rotation set: A > B (max gap 2.0 s)', 'message')

if fails > 0 then
  error(fails .. ' failure(s)')
end
print('autorotation_test: OK')
