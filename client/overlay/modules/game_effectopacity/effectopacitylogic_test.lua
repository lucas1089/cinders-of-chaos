-- luajit effectopacitylogic_test.lua && lua5.3 effectopacitylogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'effectopacitylogic.lua')
local L = EffectOpacityLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(L.KEY, 'opacityEffects', 'the base key is kept')
eq(L.MIN, 25, 'minimum 25%')
eq(L.MAX, 100, 'maximum 100%')
eq(L.DEFAULT, 100, 'default 100%')

-- clamp
eq(L.clamp(nil), 100, 'unset -> default')
eq(L.clamp('abc'), 100, 'junk -> default')
eq(L.clamp(0 / 0), 100, 'nan -> default')
eq(L.clamp(math.huge), 100, 'inf -> default')
eq(L.clamp('60'), 60, 'text 60')
eq(L.clamp(0), 25, 'an old 0 -> 25')
eq(L.clamp(10), 25, 'under the floor -> 25')
eq(L.clamp(140), 100, 'over -> 100')
eq(L.clamp(62), 60, 'to the step (down)')
eq(L.clamp(63), 65, 'to the step (up)')
eq(math.type and math.type(L.clamp(55.0)) or 'integer', 'integer', 'a whole number in Lua 5.3')

-- migration: the lowest value set on any old control, clamped
eq(L.migrate({}), 100, 'nothing saved')
eq(L.migrate({ opacityEffects = 100 }), 100, 'only the base value')
eq(L.migrate({ opacityEffects = 100, ownSpellOpacity = 60 }), 60, 'own spells slider was lower')
eq(L.migrate({ opacityEffects = 80, spellOpacityOwn = 40 }), 40, 'HP/MP circle slider was lower')
eq(L.migrate({ opacityEffects = 50, ownSpellOpacity = 90, spellOpacityOwn = 70 }), 50, 'base was lowest')
eq(L.migrate({ ownSpellOpacity = 0 }), 25, 'an old 0 becomes 25')
eq(L.migrate({ opacityEffects = 'x', ownSpellOpacity = 45 }), 45, 'junk ignored')

-- plan at start
eq(L.plan(false, { opacityEffects = 100, ownSpellOpacity = 30 }), 30, 'first start: migrate')
eq(L.plan(false, {}), 100, 'first start, nothing saved: 100')
eq(L.plan(true, { opacityEffects = 70, ownSpellOpacity = 30 }), nil, 'migrated: old keys no longer count')
eq(L.plan(true, { opacityEffects = 10 }), 25, 'migrated: an out-of-range value is clamped')
eq(L.plan(true, { opacityEffects = 55 }), nil, 'migrated: an in-range value is left')
eq(L.plan(true, {}), nil, 'migrated: nothing stored, nothing to do')

-- base patch 0049: one slider, 25..100, the per-source sliders gone, the apply clamps
local f = io.open(dir .. '../../../base-patches/0049-spell-effect-opacity.patch', 'r')
if f then
  local text = f:read('*a'); f:close()
  eq(text:find("+      minimum: 25", 1, true) ~= nil, true, 'slider minimum 25')
  eq(text:find("Spell effects opacity: %s%%", 1, true) ~= nil, true, 'label')
  eq(text:find('math.max(25, math.min(100,', 1, true) ~= nil, true, 'apply clamps to 25..100')
  for _, id in ipairs({ 'ownSpellOpacity', 'otherSpellOpacity', 'creatureSpellOpacity', 'bossSpellOpacity',
      'ownSpellScrollbar', 'otherSpellScrollbar', 'creatureSpellScrollbar', 'bossSpellScrollbar' }) do
    eq(text:find('\n-      id: ' .. id .. '\n', 1, true) ~= nil, true, id .. ' removed')
    eq(text:find('\n+      id: ' .. id .. '\n', 1, true), nil, id .. ' not added back')
  end
  eq(text:find('\n+', 1, true) and text:find('%.cpp') == nil, true, 'no C++ change')
else
  eq(false, true, 'base patch 0049 read')
end

print(string.format('effectopacitylogic_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
