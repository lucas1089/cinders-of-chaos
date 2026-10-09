-- luajit buffmath_test.lua && lua5.3 buffmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'buffmath.lua')
local M = BuffMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- settings
local s = M.sanitize(nil)
eq(s.scale, 100, 'default scale'); eq(s.locked, false, 'unlocked'); eq(s.hideEmpty, true, 'hides when empty'); eq(s.perRow, 10, 'per row'); eq(s.x, nil, 'no position')
s = M.sanitize({ scale = 133, locked = true, shown = false, timers = false, hideEmpty = false, perRow = 99, x = 12.7, y = 40 })
eq(s.scale, 130, 'scale rounds to a step'); eq(s.locked, true, 'locked'); eq(s.shown, false, 'hidden'); eq(s.timers, false, 'no timers')
eq(s.hideEmpty, false, 'show when empty'); eq(s.perRow, 16, 'per row capped'); eq(s.x, 12, 'x'); eq(s.y, 40, 'y')
eq(M.sanitize({ scale = 5 }).scale, 70, 'scale floor'); eq(M.sanitize({ scale = 900 }).scale, 180, 'scale cap')
eq(M.sanitize({ scale = 'big', locked = 'yes', perRow = 0 }).scale, 100, 'bad scale'); eq(M.sanitize({ locked = 'yes' }).locked, false, 'bad flag')
eq(M.sanitize({ perRow = 0 }).perRow, 4, 'per row floor'); eq(M.sanitize({ x = 5 }).x, nil, 'half a position is none')
eq(M.iconSize(100), 26, 'size 100%'); eq(M.iconSize(150), 39, 'size 150%'); eq(M.iconSize(70), 18, 'size 70%'); eq(M.iconSize(1000), 47, 'size capped')
eq(M.stepScale(100, 1), 110, 'step up'); eq(M.stepScale(70, -1), 70, 'step floor'); eq(M.stepScale(180, 1), 180, 'step cap')
local x, y = M.clampPosition(-500, -50, 100, 30, 800, 600)
eq(x, -76, 'clamped left'); eq(y, 0, 'clamped top')
x, y = M.clampPosition(5000, 5000, 100, 30, 800, 600)
eq(x, 776, 'clamped right'); eq(y, 576, 'clamped bottom')
x, y = M.clampPosition(100, 100, 100, 30, 800, 600)
eq(x, 100, 'inside stays'); eq(y, 100, 'inside stays y')

-- full / diff
local st = {}
local now = 1000
local list = { { k = 'haste', n = 'Haste', d = 'Faster.', i = 'spell:utani hur', t = 0, l = 12000 },
  { k = 'poison', n = 'Poisoned', d = 'Hurts.', i = 'cond:00', t = 1, l = 6500 },
  { k = 'rage', n = 'Rage +20%', d = 'Hit harder.', i = 'buff:rage', t = 0, s = 20 } }
eq(M.apply(st, 'full', { list = list }, now), true, 'full changes')
eq(M.count(st), 3, 'three entries')
eq(st.buffs.haste.endAt, 1012, 'end time from ms'); eq(st.buffs.poison.debuff, true, 'debuff'); eq(st.buffs.rage.endAt, nil, 'no timer'); eq(st.buffs.rage.stacks, 20, 'stacks')
eq(M.remaining(st.buffs.haste, 1004), 8, 'time left'); eq(M.remaining(st.buffs.haste, 1100), 0, 'never negative'); eq(M.remaining(st.buffs.rage, 1004), nil, 'no time')
-- update: recast and stacks; the order stays
eq(M.apply(st, 'diff', { upd = { { k = 'haste', l = 20000 }, { k = 'rage', s = 33 }, { k = 'nothing', l = 1 } } }, 1004), true, 'update changes')
eq(st.buffs.haste.endAt, 1024, 'recast end'); eq(st.buffs.rage.stacks, 33, 'new stacks'); eq(st.buffs.rage.endAt, nil, 'still no timer'); eq(M.count(st), 3, 'unknown update ignored')
-- add and delete
eq(M.apply(st, 'diff', { add = { { k = 'burning', n = 'Burning', d = '', i = 'cond:01', t = 1, l = 3000 } }, del = { 'poison' } }, 1005), true, 'add and delete')
eq(st.buffs.poison, nil, 'poison gone'); eq(st.buffs.burning.endAt, 1008, 'burning added'); eq(M.count(st), 3, 'still three')
eq(M.apply(st, 'diff', { del = { 'poison' } }, 1005), false, 'deleting nothing changes nothing')
eq(M.apply(st, 'diff', {}, 1005), false, 'empty diff'); eq(M.apply(st, 'hello', {}, 1005), false, 'unknown action')
-- an add that replaces keeps its place in the row
local seqBefore = st.buffs.haste.seq
M.apply(st, 'diff', { add = { { k = 'haste', n = 'Haste II', d = 'x', i = 'buff:haste', t = 0, l = 5000 } } }, 1006)
eq(st.buffs.haste.seq, seqBefore, 'replaced entry keeps its place'); eq(st.buffs.haste.name, 'Haste II', 'replaced')
-- bad input never breaks it
eq(M.apply(st, 'diff', { add = { 5, 'x', {}, { k = '' }, { k = 7 } }, upd = { 'z', 3 }, del = { 1, {} } }, 1007), false, 'garbage is ignored')
eq(M.apply(st, 'full', 'nope', 1007), true, 'a full with garbage empties the bar'); eq(M.count(st), 0, 'empty')
-- rows
M.apply(st, 'full', { list = list }, 2000)
local buffs, debuffs = M.rows(st)
eq(#buffs, 2, 'two buffs'); eq(#debuffs, 1, 'one debuff'); eq(buffs[1].key, 'haste', 'server order'); eq(buffs[2].key, 'rage', 'server order 2'); eq(debuffs[1].key, 'poison', 'debuff row')
-- pruning
eq(M.expired(st.buffs.haste, 2013), false, 'inside the grace'); eq(M.expired(st.buffs.haste, 2014), true, 'past the grace'); eq(M.expired(st.buffs.rage, 99999), false, 'no timer never expires')
eq(M.prune(st, 2020), 2, 'prunes the timed ones'); eq(M.count(st), 1, 'the timer-less stays')
M.clear(st); eq(M.count(st), 0, 'clear')

-- time text
eq(M.format(nil), '', 'no time'); eq(M.format(0), '0s', 'zero'); eq(M.format(0.2), '1s', 'rounds up'); eq(M.format(45), '45s', '45s'); eq(M.format(59.2), '1:00', 'just under a minute')
eq(M.format(60), '1:00', 'a minute'); eq(M.format(65), '1:05', '1:05'); eq(M.format(599), '9:59', '9:59'); eq(M.format(600), '10m', '10m'); eq(M.format(3599), '59m', 'just under an hour')
eq(M.format(3600), '1h', 'an hour'); eq(M.format(7300), '2h', 'hours'); eq(M.format(90000), '1d', 'a day')
eq(M.formatLong(45), '45s', 'long 45'); eq(M.formatLong(303), '5m 03s', 'long 303'); eq(M.formatLong(3909), '1h 05m 09s', 'long 3909'); eq(M.formatLong(-5), '0s', 'long negative')

-- grid
local cells, w, h = M.grid(5, 3, 26, 2, 4, 14)
eq(#cells, 5, 'cells'); eq(cells[1].x, 4, 'first x'); eq(cells[1].y, 14, 'first y'); eq(cells[3].x, 4 + 2 * 28, 'third x'); eq(cells[4].x, 4, 'wraps'); eq(cells[4].y, 14 + 28, 'second row')
eq(w, 3 * 28 - 2, 'grid width'); eq(h, 2 * 28 - 2, 'grid height')
cells, w, h = M.grid(0, 3, 26, 2, 0, 0); eq(#cells, 0, 'no cells'); eq(w, 0, 'no width'); eq(h, 0, 'no height')

-- tooltip
local tip = M.tooltip({ name = 'Haste', desc = 'Faster.', debuff = false, endAt = 1065, stacks = nil }, 1000)
eq(tip, 'Haste\nFaster.\nTime left: 1m 05s', 'tooltip')
tip = M.tooltip({ name = 'Rage +20%', desc = '', debuff = true, endAt = nil, stacks = 20 }, 1000)
eq(tip, 'Rage +20%  (debuff)\nStacks: 20\nNo time limit', 'tooltip debuff, stacks, no timer')

-- icons
local k, a = M.parseIcon('spell:utani hur'); eq(k, 'spell', 'spell kind'); eq(a, 'utani hur', 'spell words')
k, a = M.parseIcon('cond:05'); eq(k, 'cond', 'cond'); eq(a, '05', 'cond number')
k, a = M.parseIcon('buff:world_xp'); eq(k, 'buff', 'own'); eq(a, 'world_xp', 'own name')
eq(M.parseIcon('http:evil'), nil, 'unknown scheme'); eq(M.parseIcon(nil), nil, 'nil icon'); eq(M.parseIcon(''), nil, 'empty icon')
eq(M.condPath('05'), '/images/arcs/conditions/player-state-flags-05', 'cond path'); eq(M.condPath('../x'), nil, 'cond path is checked')
eq(M.ownPath('world_xp'), '/images/game/buffs/world_xp', 'own path'); eq(M.ownPath('../../x'), nil, 'own path is checked')

if fails > 0 then os.exit(1) end
print('buff bar tests OK (' .. checks .. ' checks)')
