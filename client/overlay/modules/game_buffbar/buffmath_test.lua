-- luajit buffmath_test.lua && lua5.3 buffmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'buffmath.lua')
local M = BuffMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- settings: only show and countdown are left; an old saved position, size, icons per row or lock is dropped
local s = M.sanitize(nil)
eq(s.shown, true, 'shown by default'); eq(s.timers, true, 'countdown by default')
s = M.sanitize({ scale = 133, locked = true, shown = false, timers = false, hideEmpty = false, perRow = 99, x = 12.7, y = 40 })
eq(s.shown, false, 'hidden'); eq(s.timers, false, 'no timers')
eq(s.x, nil, 'old x dropped'); eq(s.y, nil, 'old y dropped'); eq(s.scale, nil, 'old scale dropped'); eq(s.perRow, nil, 'old per row dropped')
eq(s.locked, nil, 'old lock dropped'); eq(s.hideEmpty, nil, 'old hide-when-empty dropped')
eq(M.sanitize({ shown = 'yes' }).shown, true, 'bad flag'); eq(M.sanitize('junk').timers, true, 'bad node')

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
-- order: buffs first, then debuffs, each in the server's order
M.apply(st, 'full', { list = list }, 2000)
local order, nBuffs = M.ordered(st)
eq(#order, 3, 'three drawn'); eq(nBuffs, 2, 'two buffs'); eq(order[1].key, 'haste', 'server order'); eq(order[2].key, 'rage', 'server order 2')
eq(order[3].key, 'poison', 'debuff after the buffs'); eq(M.orderKey(order), 'haste,rage,poison', 'order key')
M.apply(st, 'diff', { add = { { k = 'slow', n = 'Slowed', t = 1, l = 9000 }, { k = 'regen', n = 'Regeneration', t = 0, l = 9000 } } }, 2000)
order = M.ordered(st)
eq(M.orderKey(order), 'haste,rage,regen,poison,slow', 'a new buff goes before the debuffs, a new debuff at the end')
M.apply(st, 'diff', { del = { 'slow', 'regen' } }, 2000)
eq(M.orderKey(M.ordered({})), '', 'nothing to draw')
-- pruning
eq(M.expired(st.buffs.haste, 2013), false, 'inside the grace'); eq(M.expired(st.buffs.haste, 2014), true, 'past the grace'); eq(M.expired(st.buffs.rage, 99999), false, 'no timer never expires')
eq(M.prune(st, 2020), 2, 'prunes the timed ones'); eq(M.count(st), 1, 'the timer-less stays')
M.clear(st); eq(M.count(st), 0, 'clear')

-- time text
eq(M.format(nil), '', 'no time'); eq(M.format(0), '0s', 'zero'); eq(M.format(0.2), '1s', 'rounds up'); eq(M.format(45), '45s', '45s'); eq(M.format(59.2), '1:00', 'just under a minute')
eq(M.format(60), '1:00', 'a minute'); eq(M.format(65), '1:05', '1:05'); eq(M.format(599), '9:59', '9:59'); eq(M.format(600), '10m', '10m'); eq(M.format(3599), '59m', 'just under an hour')
eq(M.format(3600), '1h', 'an hour'); eq(M.format(7300), '2h', 'hours'); eq(M.format(90000), '1d', 'a day')
eq(M.formatLong(45), '45s', 'long 45'); eq(M.formatLong(303), '5m 03s', 'long 303'); eq(M.formatLong(3909), '1h 05m 09s', 'long 3909'); eq(M.formatLong(-5), '0s', 'long negative')

-- flow: rows as wide as the plate (300 px widget, drawn 7..297 -> 290 px), 26 px icons 2 px apart -> 10 per row
eq(M.perRow(290, 26, 2), 10, 'ten per row on the plate'); eq(M.perRow(10, 26, 2), 1, 'at least one per row')
eq(M.perRow(278, 26, 2), 10, 'ten fit exactly'); eq(M.perRow(277, 26, 2), 9, 'one pixel short')
local cells, rows, h = M.flow(0, 290)
eq(#cells, 0, 'no cells'); eq(rows, 0, 'no rows'); eq(h, 0, 'empty bar takes no space')
cells, rows, h = M.flow(3, 290)
eq(rows, 1, 'one row'); eq(h, 26, 'one row high'); eq(cells[1].x, 0, 'first at the left'); eq(cells[1].y, 0, 'first at the top'); eq(cells[3].x, 56, 'third x')
cells, rows, h = M.flow(10, 290)
eq(rows, 1, 'a full row is still one'); eq(cells[10].x, 252, 'last of a row'); eq(cells[10].x + 26 <= 290, true, 'inside the plate width')
cells, rows, h = M.flow(11, 290)
eq(rows, 2, 'the 11th starts a new row'); eq(cells[11].x, 0, 'new row at the left'); eq(cells[11].y, 28, 'new row below'); eq(h, 54, 'two rows high')
cells, rows, h = M.flow(23, 290)
eq(rows, 3, '23 icons: three rows'); eq(cells[21].y, 56, 'third row'); eq(cells[23].x, 56, '23rd x'); eq(h, 82, 'three rows high')
for i, c in ipairs(cells) do
  if c.x < 0 or c.x + 26 > 290 then eq(c.x, 'inside', 'cell ' .. i .. ' inside the row') end
end

-- attach: under the plate, left-aligned with its drawn edge, as wide as the drawn plate; hidden with it
local spot = M.attach({ x = 34, y = 40, width = 300, height = 96, visible = true })
eq(spot.x, 41, 'drawn left edge'); eq(spot.y, 138, 'under the level badge'); eq(spot.width, 290, 'as wide as the drawn plate'); eq(spot.shown, true, 'shown')
spot = M.attach({ x = 500, y = 300, width = 300, height = 96 })
eq(spot.x, 507, 'follows a moved plate x'); eq(spot.y, 398, 'follows a moved plate y'); eq(spot.shown, true, 'visible unless told')
eq(M.attach({ x = 0, y = 0, width = 300, height = 96, visible = false }).shown, false, 'hidden with the plate')
eq(M.attach({ x = 0, y = 0, width = 5, height = 96 }).width, 26, 'never narrower than an icon')
spot = M.attach(nil, { x = 0, y = 0 })
eq(spot.x, 41, 'no plate: its spot x'); eq(spot.y, 138, 'no plate: its spot y'); eq(spot.width, 290, 'no plate: its width'); eq(spot.shown, true, 'no plate: shown')
spot = M.attach(nil, { x = 200, y = -80 })
eq(spot.x, 241, 'no plate: relative to the view x'); eq(spot.y, 58, 'no plate: relative to the view y')

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
eq(M.ownName('buff:world_xp', 'x'), 'world_xp', 'own icon'); eq(M.ownName('cond:00', 'poison'), 'poison', 'cond: the key')
eq(M.ownName('spell:utani hur', 'haste'), 'haste', 'spell: the key'); eq(M.ownName('buff:../x', 'regen'), 'regen', 'bad name: the key')
eq(M.ownName('junk', '../x'), 'spellbuff', 'nothing valid'); eq(M.ownName(nil, nil), 'spellbuff', 'no spec, no key')
eq(M.OWN_CLIP, '0 0 ' .. M.ICON_SIZE .. ' ' .. M.ICON_SIZE, 'own icons are drawn 1:1 at the cell size')
eq(M.ownPath('world_xp'), '/images/game/buffs/world_xp', 'own path'); eq(M.ownPath('../../x'), nil, 'own path is checked')

if fails > 0 then os.exit(1) end
print('buff bar tests OK (' .. checks .. ' checks)')
