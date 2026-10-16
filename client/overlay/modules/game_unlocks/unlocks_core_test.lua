-- luajit client/overlay/modules/game_unlocks/unlocks_core_test.lua (and lua5.3), from the repo root
dofile('client/overlay/modules/game_unlocks/unlocks_core.lua')
local U = UnlocksCore

local n = 0
local function eq(a, b, m)
  n = n + 1
  if a ~= b then error((m or '') .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b), 2) end
end

-- ---------------------------------------------------------------- one entry
eq(U.isLocked({ 128, 'Citizen', 3 }), false, 'a stock tuple is owned')
eq(U.isLocked({ 128, 'Citizen', 0, locked = true }), true, 'a catalogue tuple is locked')
eq(U.isLocked({ id = 4, kind = 'spellskin', owned = true }), false, 'an owned cosmetic row')
eq(U.isLocked({ id = 4, kind = 'spellskin' }), true, 'a cosmetic row not owned')
eq(U.isLocked({ id = 0, kind = 'killfx' }), false, 'the default row is never locked')
eq(U.isLocked({ key = 'x', collection = true, owned = nil, kind = 'mount' }), true, 'a Collection row not earned')
eq(U.isLocked(nil), false, 'nothing is not locked')
eq(U.canUse({ 1, 'x', locked = true }), false, 'a locked entry cannot be used')
eq(U.canUse({ 1, 'x' }), true, 'an owned entry can')
eq(U.tooltip({ 1, 'x', locked = true, how = 'Store' }), 'Not unlocked yet.\nHow to get it: Store', 'locked tooltip')
eq(U.tooltip({ 1, 'x', locked = true }), 'Not unlocked yet.', 'locked, source unknown')
eq(U.tooltip({ 1, 'x', how = 'Free' }), 'Unlocked.\nFree', 'owned with a source')
eq(U.tooltip({ 1, 'x' }), nil, 'owned, no source: no tooltip')

-- ---------------------------------------------------------------- filter and count
local list = { { 1, 'a', locked = true }, { 2, 'b' }, { 3, 'c', locked = true }, { 4, 'd' } }
local all = U.filter(list, false)
eq(#all, 4, 'everything shown')
eq(all[1][1] .. all[2][1] .. all[3][1] .. all[4][1], '2413', 'owned first, then locked, each in order')
local mine = U.filter(list, true)
eq(#mine, 2, 'Only mine hides the locked')
eq(mine[1][1] .. mine[2][1], '24', 'owned in order')
local have, total = U.count(list)
eq(have .. '/' .. total, '2/4', 'count')
local rows = { { id = 0, kind = 'killfx' }, { id = 101, kind = 'killfx', owned = true }, { id = 102, kind = 'killfx' } }
eq(#U.filter(rows, true), 2, 'Cosmetics: the default and the owned stay')

-- ---------------------------------------------------------------- outfit window merge
local catalogue = {
  { l = 128, n = 'Citizen', o = true, a = 3, s = 'Free' },
  { l = 129, n = 'Hunter', o = true, a = 0 },
  { l = 1455, n = 'Wingbound', s = 'Boss: Varkhul' },
  { l = 2073, n = 'Warrior Class', o = true, s = 'Class: Warrior Class' }, -- owned by the catalogue, not in the packet
}
local stock = { { 128, 'Citizen', 3 }, { 129, 'Hunter', 0 } }
local d = U.display('outfit', stock, catalogue)
eq(#d, 4, 'stock plus the missing catalogue looks')
eq(d[1], stock[1], 'stock entries kept as they are')
eq(d[1].how, 'Free', 'stock entry gets its source')
eq(d[3][1], 1455, 'locked look appended')
eq(d[3][2], 'Wingbound', 'with its name')
eq(d[3][3], 0, 'no addons')
eq(d[3].locked, true, 'locked')
eq(d[3].how, 'Boss: Varkhul', 'its source')
eq(d[4].locked, true, 'not in the packet = locked, whatever the catalogue says')
eq(#U.display('outfit', stock, nil), 2, 'no catalogue: the stock list')
eq(#U.display('outfit', nil, catalogue), 4, 'no stock list: all locked')

local auras = U.display('aura', { { 932, 0, 932, 'Fire Essence' } }, { { l = 932, n = 'Fire Essence' }, { l = 933, n = 'Shock' } })
eq(#auras, 2, 'auras merged')
eq(auras[2][3] .. ':' .. auras[2][4], '933:Shock', 'aura tuple {id, category, clientId, name}')
local mounts = U.display('mount', { { 369, 'Racing Bird', 0 } }, { { l = 368, n = 'Widow Queen', s = 'Store' }, { l = 369, n = 'Racing Bird' } })
eq(mounts[1][1], 369, 'owned mount first')
eq(mounts[2].locked, true, 'Widow Queen locked')
local shaders = U.display('shader', { { id = 19, name = 'chaos_ember_glow', label = 'Ember Glow' } },
  { { n = 'chaos_ember_glow', s = 'Store' }, { n = 'chaos_frost_rime', s = 'Store' } }, function(name) return 'L:' .. name end)
eq(#shaders, 2, 'shaders merged by name')
eq(shaders[1].how, 'Store', 'owned shader source')
eq(shaders[2].name, 'chaos_frost_rime', 'locked shader name')
eq(shaders[2].label, 'L:chaos_frost_rime', 'locked shader label')
eq(shaders[2].locked, true, 'locked shader')

-- ---------------------------------------------------------------- Ok and presets
local sets = U.lockedSets({ outfit = d, mount = mounts, aura = auras, shader = shaders })
eq(sets.outfit[1455], true, 'locked outfit set')
eq(sets.outfit[128], nil, 'owned outfit not in the set')
eq(sets.mount[368], true, 'locked mount set')
eq(sets.shader.chaos_frost_rime, true, 'locked shader set')
eq(#U.lockedParts({ type = 128, mount = 369 }, sets), 0, 'all owned: Ok')
local parts = U.lockedParts({ type = 1455, mount = 368, aura = 933, shader = 'chaos_frost_rime' }, sets)
eq(table.concat(parts, ','), 'outfit,mount,aura,shader', 'every locked part')
eq(#U.lockedParts({ type = 128, mount = 368 }, sets, { mounted = false }), 0, 'an unused mount does not count')
eq(#U.lockedParts({ type = 128, aura = 933 }, sets, { aura = false }), 0, 'an unused aura does not count')
eq(U.presetLocked({ type = 1455 }, sets), true, 'a preset with a locked look')
eq(U.presetLocked({ type = 128, shader = 'chaos_ember_glow' }, sets), false, 'a preset of owned parts')

-- ---------------------------------------------------------------- the wardrobe message
local w = U.readWardrobe({ sex = 1, hash = 'abcd', outfit = { { l = 128, n = 'Citizen', o = 1, a = 3, s = 'Free' }, { l = 0 }, 'x' },
  mount = { { l = 368, n = 'Widow Queen' } }, shader = { { n = 'blue', o = 1 }, { n = 5 } } })
eq(#w.outfit, 1, 'bad outfit entries dropped')
eq(w.outfit[1].o, true, 'owned flag')
eq(w.mount[1].o, false, 'not owned')
eq(#w.shader, 1, 'shader without a name dropped')
eq(#w.wings, 0, 'missing kind = empty')
eq(U.readWardrobe('x'), nil, 'not a table')

-- ---------------------------------------------------------------- Only mine per character
local node = U.setOnlyMine(nil, 'Ann', 'outfit', true)
eq(U.onlyMine(node, 'Ann', 'outfit'), true, 'set for Ann')
eq(U.onlyMine(node, 'Bob', 'outfit'), false, 'not for Bob')
eq(U.onlyMine(node, 'Ann', 'mount'), false, 'per list')
local node2 = U.setOnlyMine(node, 'Ann', 'outfit', false)
eq(U.onlyMine(node2, 'Ann', 'outfit'), false, 'cleared')
eq(node2.Ann, nil, 'an empty character is dropped')
eq(U.onlyMine(node, 'Ann', 'outfit'), true, 'the old node is not changed')
eq(U.onlyMine(U.setOnlyMine(node, '', 'outfit', true), '', 'outfit'), false, 'no character, no setting')

print(string.format('unlocks_core_test: %d checks OK', n))
