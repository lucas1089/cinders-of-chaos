-- luajit effectopacitylogic_test.lua && lua5.3 effectopacitylogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'effectopacitylogic.lua')
local L = EffectOpacityLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function read(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local text = f:read('*a'); f:close()
  return text
end

eq(L.KEY, 'opacityEffects', 'the base key is kept for my effects')
eq(L.KEY_OTHERS, 'opacityOtherEffects', 'the other players key')
eq(L.MIN, 0, 'minimum 0% (warnings are exempt)')
eq(L.MAX, 100, 'maximum 100%')
eq(L.STEP, 5, 'steps of 5')
eq(L.DEFAULT, 100, 'default 100%')
eq(L.OPCODE, 164, 'the opcode')

-- clamp
eq(L.clamp(nil), 100, 'unset -> default')
eq(L.clamp('abc'), 100, 'junk -> default')
eq(L.clamp(0 / 0), 100, 'nan -> default')
eq(L.clamp(math.huge), 100, 'inf -> default')
eq(L.clamp('60'), 60, 'text 60')
eq(L.clamp(0), 0, '0 is allowed')
eq(L.clamp(2), 0, '2 -> 0 on the grid')
eq(L.clamp(3), 5, '3 -> 5 on the grid')
eq(L.clamp(-20), 0, 'under 0 -> 0')
eq(L.clamp(140), 100, 'over -> 100')
eq(L.clamp(62), 60, 'to the step (down)')
eq(L.clamp(63), 65, 'to the step (up)')
eq(math.type and math.type(L.clamp(55.0)) or 'integer', 'integer', 'a whole number in Lua 5.3')

-- migration of the old sliders (0049): the lowest value set on any old control
eq(L.migrate({}), 100, 'nothing saved')
eq(L.migrate({ opacityEffects = 100 }), 100, 'only the base value')
eq(L.migrate({ opacityEffects = 100, ownSpellOpacity = 60 }), 60, 'own spells slider was lower')
eq(L.migrate({ opacityEffects = 80, spellOpacityOwn = 40 }), 40, 'HP/MP circle slider was lower')
eq(L.migrate({ opacityEffects = 50, ownSpellOpacity = 90, spellOpacityOwn = 70 }), 50, 'base was lowest')
eq(L.migrate({ ownSpellOpacity = 0 }), 0, 'a 0 stays 0')
eq(L.migrate({ opacityEffects = 'x', ownSpellOpacity = 45 }), 45, 'junk ignored')

-- plan at start
eq(L.plan(false, { opacityEffects = 100, ownSpellOpacity = 30 }), 30, 'first start: migrate')
eq(L.plan(false, {}), 100, 'first start, nothing saved: 100')
eq(L.plan(true, { opacityEffects = 70, ownSpellOpacity = 30 }), nil, 'migrated: old keys no longer count')
eq(L.plan(true, { opacityEffects = 140 }), 100, 'migrated: an out-of-range value is clamped')
eq(L.plan(true, { opacityEffects = 10 }), nil, 'migrated: 10 is in range now (0049 raised it to 25)')
eq(L.plan(true, { opacityEffects = 55 }), nil, 'migrated: an in-range value is left')
eq(L.plan(true, {}), nil, 'migrated: nothing stored, nothing to do')

-- 0202: the other players' slider
eq(L.planOthers(false, {}), nil, 'first start of 0202, nothing stored: both stay at the default')
eq(L.planOthers(false, { opacityEffects = 40 }), 40, 'first start: copies my value (someone who dimmed effects keeps them dimmed)')
eq(L.planOthers(false, { opacityEffects = 100 }), 100, 'first start: 100 copied')
eq(L.planOthers(false, { opacityEffects = 62, opacityOtherEffects = 10 }), 60, 'first start: an existing value of the new key is replaced once')
eq(L.planOthers(false, { opacityEffects = 'x' }), nil, 'first start: junk is no value')
eq(L.planOthers(true, { opacityEffects = 40 }), nil, 'migrated: my value no longer counts')
eq(L.planOthers(true, { opacityOtherEffects = 30 }), nil, 'migrated: in range, left')
eq(L.planOthers(true, { opacityOtherEffects = 130 }), 100, 'migrated: out of range, clamped')
eq(L.planOthers(true, { opacityOtherEffects = -5 }), 0, 'migrated: under 0, clamped')
eq(L.planOthers(true, {}), nil, 'migrated: nothing stored')
eq(L.planOthers(true, nil), nil, 'migrated: no table')

-- when the server needs to mark
eq(L.needsMarks(100, 100), false, 'equal sliders: no marks')
eq(L.needsMarks(40, 40), false, 'equal at 40: no marks')
eq(L.needsMarks(100, 30), true, 'others dimmed: marks')
eq(L.needsMarks(20, 100), true, 'mine dimmed: marks')
eq(L.needsMarks(nil, nil), false, 'nothing stored: no marks')
eq(L.needsMarks(62, 60), false, 'the same after the grid')
eq(L.hello(true).need, 1, 'hello need 1')
eq(L.hello(false).need, 0, 'hello need 0')
eq(L.hello(nil).need, 0, 'hello without a value: 0')
eq(L.hello(true).action, 'hello', 'hello action')

-- reading the server's marks
local function msg(b, m) return { action = 'marks', data = { b = b, m = m } } end
local x, y, z, flat = L.parseMarks(msg({ 32369, 32241, 7 }, { 0, 0, 0, 3001, 0, 1, -1, 3001, 1, 2, 2, 12 }))
eq(x, 32369, 'x'); eq(y, 32241, 'y'); eq(z, 7, 'z')
eq(#flat, 12, 'three groups')
eq(flat[1], 0, 'kind'); eq(flat[7], -1, 'dy'); eq(flat[12], 12, 'missile id')
eq(L.parseMarks(nil), nil, 'no message')
eq(L.parseMarks('x'), nil, 'text')
eq(L.parseMarks({ action = 'other', data = {} }), nil, 'other action')
eq(L.parseMarks({ action = 'marks' }), nil, 'no data')
eq(L.parseMarks(msg(nil, { 0, 0, 0, 5 })), nil, 'no base')
eq(L.parseMarks(msg({ 1, 2 }, { 0, 0, 0, 5 })), nil, 'a base without z')
eq(L.parseMarks(msg({ 1, 2, 16 }, { 0, 0, 0, 5 })), nil, 'z over 15')
eq(L.parseMarks(msg({ 1, 2, -1 }, { 0, 0, 0, 5 })), nil, 'z under 0')
eq(L.parseMarks(msg({ 65535, 2, 7 }, { 0, 0, 0, 5 })), nil, 'x over the map')
eq(L.parseMarks(msg({ 1.5, 2, 7 }, { 0, 0, 0, 5 })), nil, 'a fraction')
eq(L.parseMarks(msg({ 1, 2, 7 }, {})), nil, 'no marks')
eq(L.parseMarks(msg({ 1, 2, 7 }, { 0, 0, 5 })), nil, 'a partial group only')
eq(L.parseMarks(msg({ 1, 2, 7 }, 'x')), nil, 'marks that are no list')
local _, _, _, f2 = L.parseMarks(msg({ 1, 2, 7 }, { 0, 0, 0, 5, 2, 0, 0, 5, 0, 200, 0, 5, 0, 0, 0, 0, 0, 0, 0, 70000, 1, 3, 4, 9, 0, 1 }))
eq(#f2, 8, 'a bad kind, a far offset, id 0, id 70000 and the partial group are dropped')
eq(f2[4], 5, 'the first kept')
eq(f2[8], 9, 'the missile kept')
local _, _, _, f3 = L.parseMarks(msg({ 1, 2, 7 }, { 0, 0, 0, 'a', 0, 0, 0, 7 }))
eq(#f3, 4, 'a non-number group is dropped')
local big = {}
for i = 1, 1000 do big[#big + 1] = 0; big[#big + 1] = i % 10; big[#big + 1] = 0; big[#big + 1] = i end
local _, _, _, f4 = L.parseMarks(msg({ 1, 2, 7 }, big))
eq(#f4, 4 * L.MAX_MARKS, 'capped at MAX_MARKS groups')
eq(f4[#f4], L.MAX_MARKS, 'the first groups are kept')

-- warnings: whole ids, no duplicates, in the effect id range
local seen = {}
for _, id in ipairs(L.WARNING_IDS) do
  eq(seen[id], nil, 'warning id ' .. id .. ' twice')
  seen[id] = true
  eq(id >= 1 and id <= 65535 and id == math.floor(id), true, 'warning id ' .. id .. ' in range')
end

-- base patch 0049 (history): one slider, 25..100, the per-source sliders gone, the apply clamps
local f = read(dir .. '../../../base-patches/0049-spell-effect-opacity.patch')
if f then
  eq(f:find("+      minimum: 25", 1, true) ~= nil, true, '0049: slider minimum 25')
  for _, id in ipairs({ 'ownSpellOpacity', 'otherSpellOpacity', 'creatureSpellOpacity', 'bossSpellOpacity',
      'ownSpellScrollbar', 'otherSpellScrollbar', 'creatureSpellScrollbar', 'bossSpellScrollbar' }) do
    eq(f:find('\n-      id: ' .. id .. '\n', 1, true) ~= nil, true, id .. ' removed')
    eq(f:find('\n+      id: ' .. id .. '\n', 1, true), nil, id .. ' not added back')
  end
  eq(f:find('\n+', 1, true) and f:find('%.cpp') == nil, true, '0049: no C++ change')
else
  eq(false, true, 'base patch 0049 read')
end

-- base patch 0202: two sliders 0..100, the engine part, the texts in pt-BR
local p = read(dir .. '../../../base-patches/0202-effect-opacity-by-owner.patch')
if p then
  eq(p:find('+\topacityOtherEffects = {', 1, true) ~= nil, true, '0202: the new option')
  eq(p:find('g_client.setOtherPlayerSpellEffectAlpha(v / 100)', 1, true) ~= nil, true, '0202: it sets the other alpha')
  eq(p:find('g_client.setEffectAlpha(v / 100)', 1, true) ~= nil, true, '0202: the first slider sets the own alpha')
  eq(p:find('+      id: opacityOtherEffects\n', 1, true) ~= nil, true, '0202: the new scroll bar')
  eq(p:find('-      minimum: 25', 1, true) ~= nil, true, '0202: the floor of 25 goes')
  eq(p:find('math.max(0, math.min(100,', 1, true) ~= nil, true, '0202: the apply clamps to 0..100')
  eq(p:find('+++ b/src/client/chaosfxowner.h', 1, true) ~= nil, true, '0202: the pure header')
  eq(p:find('g_client.markEffectSources', 1, true) ~= nil, true, '0202: the marks call')
  eq(p:find('setEffectAlphaExempt', 1, true) ~= nil, true, '0202: the warning list')
  eq(p:find('"setMissileAlpha"', 1, true) ~= nil, true, '0202: the missile slider is bound')
  eq(p:find('modules.game_effectopacity', 1, true) ~= nil, true, '0202: the module is told')
  -- every tr() text the patch adds has a pt-BR entry
  local pt = read(dir .. '../client_chaos_locale/pt_br.lua')
  eq(pt ~= nil, true, 'pt_br.lua read')
  if pt then
    for _, key in ipairs({
      "Opacity of my effects: %s%%", "Opacity of my effects: 100%%",
      "Opacity of other players' effects: %s%%", "Opacity of other players' effects: 100%%",
      "How strongly the spell and area effects you cast yourself are drawn (not missiles, they have their own slider).\\n0%% hides them. Boss warning circles are never faded.",
      "How strongly the effects of other players and of monsters are drawn.\\n0%% hides them. Boss warning circles are never faded.",
    }) do
      local lua = key:gsub("'", "\\'")
      eq(pt:find('["' .. key .. '"] =', 1, true) ~= nil or pt:find("['" .. lua .. "'] =", 1, true) ~= nil, true, 'pt-BR for: ' .. key:sub(1, 50))
    end
    eq(pt:find('Opacidade dos meus efeitos', 1, true) ~= nil, true, 'the owner text for my effects')
    eq(pt:find('Opacidade dos efeitos dos outros', 1, true) ~= nil, true, 'the owner text for the others')
  end
else
  eq(false, true, 'base patch 0202 read')
end

print(string.format('effectopacitylogic_test: %d checks, %d failures', checks, fails))
if fails > 0 then os.exit(1) end
