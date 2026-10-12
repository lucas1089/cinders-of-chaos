-- luajit petsview_test.lua && lua5.3 petsview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'petsview.lua')
local V = PetsView
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local state = {
  pets = {
    { species = 'ash_cat', speciesName = 'Ash Cat', name = 'Soot', look = 276, level = 21, into = 10, need = 100, pct = 10,
      abilities = { { name = 'Fetch', kind = 'utility', desc = 'Carries gold.', unlocked = true, unlockAt = 1, cooldown = 0 },
        { name = 'Mend', kind = 'combat', desc = 'Heals.', unlocked = false, unlockAt = 20, cooldown = 30 } } },
    { species = 'lantern_wisp', speciesName = 'Lantern Wisp', name = 'Lantern Wisp', look = 294, level = 3 },
  },
  catalog = {
    { key = 'ember_whelp', name = 'Ember Whelp', look = 271, how = 'Dragons.', abilities = { 'Spark Aura', 'Ward' } },
    { key = 'ash_cat', name = 'Ash Cat', look = 276, how = 'Achievement.', owned = true },
    { key = 'lantern_wisp', name = 'Lantern Wisp', look = 294, how = 'Store.', owned = true },
  },
  active = 'ash_cat', out = true, cooldowns = { summon = 3, death = 0, rename = 0 }, secondAt = 20
}

local entries = V.entries(state)
eq(#entries, 3, 'one per species')
eq(entries[1].key, 'ash_cat', 'owned first, server order')
eq(entries[2].key, 'lantern_wisp', 'owned second')
eq(entries[3].key, 'ember_whelp', 'not owned last')
eq(entries[1].how, 'Achievement.', 'how from the catalog')
eq(entries[3].owned, false, 'not owned')
eq(V.rowText(entries[1]), 'Soot', 'named pet')
eq(V.titleText(entries[1]), 'Soot (Ash Cat)', 'named pet title')
eq(V.titleText(entries[2]), 'Lantern Wisp', 'unnamed title')
eq(V.rowText(entries[2]), 'Lantern Wisp', 'unnamed pet')
eq(V.rowSub(entries[1], state), 'Level 21, out', 'active and out')
eq(V.rowSub(entries[2], state), 'Level 3', 'not active')
eq(V.rowSub(entries[3], state), 'Not owned', 'not owned')
state.out = false
eq(V.rowSub(entries[1], state), 'Level 21, resting', 'resting')
state.out = true

eq(V.pick(entries, 'lantern_wisp', 'ash_cat'), 'lantern_wisp', 'wanted kept')
eq(V.pick(entries, 'gone', 'ash_cat'), 'ash_cat', 'active next')
eq(V.pick(entries, nil, nil), 'ash_cat', 'first')
eq(V.pick({}, nil, nil), nil, 'empty')

eq(V.xpText(entries[1].pet), 'Level 21  -  10 / 100 XP (10%)', 'xp text')
eq(V.xpText({ level = 50, need = 0 }), 'Level 50 (max)', 'max level')
eq(V.xpText(nil), '', 'no pet')

local lines = V.abilityLines(entries[1], 20)
eq(#lines, 2, 'two abilities')
eq(lines[1].locked, false, 'first unlocked')
eq(lines[2].locked, true, 'second locked')
eq(lines[2].lockText, 'Unlocks at pet level 20.', 'lock text')
eq(lines[2].text, 'Heals. (every 30 s at most)', 'cooldown text')
eq(lines[1].title, 'Fetch  [utility]', 'title')
lines = V.abilityLines(entries[3], 20)
eq(lines[2].text, 'From level 20.', 'catalog ability')

local st = V.statusText(state)
assert(st:find('with you') and st:find('3 s'), 'status: ' .. st)
st = V.statusText({ active = 'x', rest = 'Your pet waits.', cooldowns = { death = 40 }, zone = 'utility (a rift)' })
assert(st:find('recovering') and st:find('waits') and st:find('utility abilities only'), 'status 2: ' .. st)
eq(V.statusText({ cooldowns = {} }), 'No pet is out.', 'no pet')

local b = V.buttons(entries[1], state)
eq(b.summon, false, 'active: no summon'); eq(b.dismiss, true, 'active: dismiss'); eq(b.rename, true, 'rename')
b = V.buttons(entries[2], state)
eq(b.summon, true, 'other owned: summon'); eq(b.dismiss, false, 'other owned: no dismiss')
b = V.buttons(entries[3], state)
eq(b.summon, false, 'not owned'); eq(b.rename, false, 'not owned rename')

eq(V.cleanName('  Mr Whiskers '), 'Mr Whiskers', 'trim')
eq(V.cleanName('   '), nil, 'empty')

assert(V.applyXp(state, { species = 'lantern_wisp', level = 4, xp = 30, into = 2, need = 20, pct = 10 }), 'xp applied')
eq(state.pets[2].level, 4, 'level from xp message')
assert(not V.applyXp(state, { species = 'nope' }), 'unknown species')

if fails > 0 then error(fails .. ' failure(s)') end
print('petsview: all asserts passed')
