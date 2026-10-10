-- luajit partymath_test.lua && lua5.3 partymath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'partymath.lua')
local M = PartyMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- settings
local s = M.sanitize(nil)
eq(s.scale, 100, 'scale'); eq(s.showSelf, false, 'own frame off by default'); eq(s.showBuffs, true, 'buffs'); eq(s.follow, true, 'follow'); eq(s.shown, true, 'shown'); eq(s.x, nil, 'no position')
s = M.sanitize({ scale = 61, showSelf = true, locked = true, showNumbers = false, x = 5, y = 9.9 })
eq(s.scale, 70, 'floor'); eq(s.showSelf, true, 'own frame on'); eq(s.locked, true, 'locked'); eq(s.showNumbers, false, 'no numbers'); eq(s.x, 5, 'x'); eq(s.y, 9, 'y')
eq(M.sanitize({ scale = 400 }).scale, 150, 'cap'); eq(M.sanitize({ showSelf = 'yes' }).showSelf, false, 'bad flag'); eq(M.sanitize({ x = 'a', y = 2 }).x, nil, 'bad position')
eq(M.stepScale(100, 1), 110, 'step'); eq(M.stepScale(150, 1), 150, 'step cap'); eq(M.stepScale(70, -1), 70, 'step floor')

local x, y = M.clampPosition(-500, -50, 100, 30, 800, 600)
eq(x, -76, 'clamped left'); eq(y, 0, 'clamped top')
x, y = M.clampPosition(5000, 5000, 100, 30, 800, 600)
eq(x, 776, 'clamped right'); eq(y, 576, 'clamped bottom')
x, y = M.clampPosition(100, 100, 100, 30, 800, 600)
eq(x, 100, 'inside stays'); eq(y, 100, 'inside stays y')

-- state
local state = {}
local data = { leader = 7, members = {
  { i = 7, n = 'Aria', lv = 312, vc = 8, h = 4200, H = 5000, m = 900, M = 1200, p = 84, dz = 0, d = 0, f = 17, o = { t = 128, h = 1, b = 2, l = 3, f = 4, a = 3 },
    b = { { i = 'cond:00', t = 1, l = 4000 }, { i = 'spell:utani hur', t = 0, l = 9000 } } },
  { i = 9, n = 'Boran', lv = 301, vc = 21, h = 120, H = 3000, m = 2900, M = 3000, p = 4, dz = -1, d = 14, f = 2 },
  { i = 11, n = 'Cael', lv = 150, vc = 3, p = 50, dz = 2, far = 1, f = 0 },
  { i = 12, n = '', lv = 1 }, 'junk', { n = 'x' } } }
eq(M.apply(state, data, 100), true, 'apply')
eq(#state.members, 3, 'garbage dropped'); eq(state.leader, 7, 'leader'); eq(state.at, 100, 'time')
local a, b, c = state.members[1], state.members[2], state.members[3]
eq(a.hp, 4200, 'hp'); eq(a.outfit.addons, 3, 'outfit'); eq(#a.buffs, 2, 'buffs'); eq(a.buffs[1].debuff, true, 'debuff'); eq(a.buffs[1].endAt, 104, 'buff end'); eq(a.buffs[2].debuff, false, 'buff')
eq(c.far, true, 'far'); eq(c.hp, nil, 'no exact health far'); eq(c.pct, 50, 'rough health'); eq(c.dz, 2, 'floors')
eq(M.inParty(state), true, 'in party')
eq(M.apply(state, { members = {} }, 101), true, 'empty state'); eq(M.inParty(state), false, 'left the party'); eq(state.leader, nil, 'no leader')
M.apply(state, data, 102); M.clear(state); eq(#state.members, 0, 'cleared'); eq(state.at, nil, 'cleared time')
M.apply(state, 'junk', 5); eq(#state.members, 0, 'garbage state')
M.apply(state, data, 100)
a, b, c = state.members[1], state.members[2], state.members[3]

-- flags
eq(M.flag(a, 'leader'), true, 'leader'); eq(M.flag(a, 'self'), true, 'self'); eq(M.flag(a, 'fight'), false, 'no fight')
eq(M.flag(b, 'fight'), true, 'fight'); eq(M.flag(b, 'leader'), false, 'not leader'); eq(M.flag(c, 'dead'), false, 'not dead')
eq(M.flag({ flags = 4 }, 'dead'), true, 'dead'); eq(M.flag({ flags = 8 }, 'offline'), true, 'offline'); eq(M.flag({ flags = 31 }, 'self'), true, 'all flags'); eq(M.flag(a, 'bogus'), false, 'unknown flag')
eq(#M.visible(state, false), 2, 'own frame hidden'); eq(#M.visible(state, true), 3, 'own frame shown'); eq(M.visible(state, false)[1].name, 'Boran', 'order kept')
eq(M.viewerIsLeader(state), true, 'viewer is leader'); state.members[1].flags = 1; eq(M.viewerIsLeader(state), false, 'no self flag: not leader'); state.members[1].flags = 17
eq(M.stale(state, 104), false, 'fresh'); eq(M.stale(state, 105), true, 'stale'); eq(M.stale({}, 999), false, 'never had one')

-- texts
eq(M.hpText(a), '4200 / 5000', 'hp text'); eq(M.hpText(c), '~50%', 'far hp text'); eq(M.mpText(a), '900 / 1200', 'mp text'); eq(M.mpText(c), '', 'far mp text')
eq(M.short(120000), '120k', 'short k'); eq(M.short(12500000), '12.5m', 'short m'); eq(M.short(99999), '99999', 'short below')
eq(M.mpPct(a), 75, 'mp pct'); eq(M.mpPct(c), 0, 'far mp pct'); eq(M.mpPct({ mp = 1, mpMax = 0 }), 0, 'no max')
eq(M.hpColor(100), '#3a9a48', 'green'); eq(M.hpColor(60), '#c2a024', 'yellow at 60'); eq(M.hpColor(30), '#c0281e', 'red at 30'); eq(M.hpColor(0), '#c0281e', 'red')
local d1, n1 = M.floorMark(-2); eq(d1, 'up', 'above'); eq(n1, 2, 'two floors')
d1, n1 = M.floorMark(1); eq(d1, 'down', 'below'); eq(n1, 1, 'one floor'); eq(M.floorMark(0), nil, 'same floor'); eq(M.floorMark(nil), nil, 'no floor')
eq(M.distanceText(a), '', 'own distance'); eq(M.distanceText(b), '14 sq', 'distance'); eq(M.distanceText(c), 'far', 'far')
eq(M.stateWord(b, false), 'fight', 'fight word'); eq(M.stateWord({ flags = 6 }, false), 'dead', 'dead beats fight'); eq(M.stateWord({ flags = 14 }, false), 'offline', 'offline beats all')
eq(M.stateWord(b, true), 'offline', 'stale is offline'); eq(M.stateWord(c, false), nil, 'no word')
local name, col = M.vocation(8); eq(name, 'Juggernaut', 'vocation'); eq(col, '#d9743a', 'warrior colour')
eq(M.vocation(14), 'Berserker', 'berserker'); eq((select(2, M.vocation(14))), col, 'line colour is shared'); eq(M.vocation(25), 'Sentinel', 'sentinel'); eq(M.vocation(99), 'Adventurer', 'unknown vocation')

-- layout
eq(M.scaled(44, 100), 44, 'scaled 100'); eq(M.scaled(44, 150), 66, 'scaled 150'); eq(M.scaled(44, 10), 31, 'scaled floor')
local set = M.sanitize({})
eq(M.frameHeight(a, set), 44 + 16, 'with buffs'); eq(M.frameHeight(b, set), 44, 'without buffs'); eq(M.frameHeight(c, set), 44, 'far: no buffs')
set.showBuffs = false; eq(M.frameHeight(a, set), 44, 'buffs off'); set.showBuffs = true
local ys, total = M.column({ a, b, c }, set, 12, 2)
eq(ys[1], 14, 'first y'); eq(ys[2], 14 + 60 + 2, 'second y'); eq(ys[3], 14 + 60 + 2 + 44 + 2, 'third y'); eq(total, 14 + 60 + 2 + 44 + 2 + 44 + 2, 'total')
local ys0, total0 = M.column({}, set, 12, 2); eq(#ys0, 0, 'no frames'); eq(total0, 14, 'only the header')

-- tooltip
eq(M.tooltip(b, 100), 'Boran  Lv 301  Lich\nHealth 120 / 3000\nMana 2900 / 3000\n1 floor above you\nIn a fight', 'tooltip')
eq(M.tooltip(c, 100), 'Cael  Lv 150  Ranger\nFar away: about 50% health\n2 floors below you', 'far tooltip')

-- default position: the layouts measured in the client (map panel, side panel, action bar; invasion HUD, the map
-- overlay's strip and corner box as drawn there). Four frames with buffs + header = 262 px.
local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
for _, L in ipairs({
  { win = { width = 1280, height = 720 }, map = { x = 0, y = -80, width = 1280, height = 800 }, right = 1102, bar = 520,
    inv = { x = 40, y = 112, w = 270, h = 240 }, strip = { x = 758, y = 468, w = 336, h = 44 }, box = { x = 742, y = 48, w = 352, h = 172 }, boxOk = false },
  { win = { width = 1366, height = 768 }, map = { x = 0, y = -85, width = 1366, height = 853 }, right = 1188, bar = 568,
    inv = { x = 40, y = 107, w = 270, h = 240 }, strip = { x = 844, y = 516, w = 336, h = 44 }, box = { x = 801, y = 48, w = 379, h = 190 }, boxOk = true },
  { win = { width = 1920, height = 1080 }, map = { x = 0, y = -120, width = 1920, height = 1200 }, right = 1742, bar = 880,
    inv = { x = 40, y = 72, w = 270, h = 240 }, strip = { x = 1398, y = 828, w = 336, h = 44 }, box = { x = 1314, y = 48, w = 420, h = 302 }, boxOk = true },
}) do
  local free = M.freeArea(L.map, L.win, { { x = L.right, y = -1, width = 178, height = L.win.height + 1 } },
    { { x = 178, y = L.bar, width = 900, height = 36 } })
  local tag = L.win.width .. 'x' .. L.win.height
  eq(free.x + free.width, L.right, tag .. ' free right'); eq(free.y, 40, tag .. ' free top'); eq(free.y + free.height, L.bar, tag .. ' free bottom')
  for _, h in ipairs({ 24 + 62, 24 + 2 * 62, 262 }) do
    local mx, my = M.defaultPosition(free, 200, h, L.map.x, L.map.y)
    local r = { x = mx + L.map.x, y = my + L.map.y, w = 200, h = h }
    eq(overlaps(r, L.inv), false, tag .. ' clear of the invasion HUD (' .. h .. ')')
    eq(overlaps(r, L.strip), false, tag .. ' clear of the overlay strip (' .. h .. ')')
    eq(r.x + r.w <= L.right and r.y >= free.y and r.y + r.h <= L.bar, true, tag .. ' inside the free view (' .. h .. ')')
    if h < 262 or L.boxOk then eq(overlaps(r, L.box), false, tag .. ' clear of the corner box (' .. h .. ')') end
  end
end
-- a big party slides up to stay above the strip
local free = { x = 0, y = 40, width = 1102, height = 480 }
local _, y = M.defaultPosition(free, 200, 400, 0, 0)
eq(y + 400 <= 520 - 44 - 8, true, 'big party above the strip')
eq(select(2, M.defaultPosition({ x = 0, y = 40, width = 300, height = 100 }, 200, 400, 0, 0)), 48, 'never above the free area')

if fails > 0 then os.exit(1) end
print('party frames tests OK (' .. checks .. ' checks)')
