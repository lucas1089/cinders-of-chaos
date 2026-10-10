-- luajit dpsmath_test.lua && lua5.3 dpsmath_test.lua (CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'dpsmath.lua')
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- settings
local s = DpsMath.sanitize(nil)
eq(s.shown, false, 'hidden by default')
eq(s.share, true, 'shares by default')
eq(s.tab, 'dmg', 'damage tab')
eq(s.seg, 'c', 'current fight')
eq(s.x, nil, 'no position')
s = DpsMath.sanitize({ shown = true, w = 5000, h = 10, tab = 'taken', seg = 17, x = 12.7, y = '40', share = 'yes' })
eq(s.shown, true, 'shown kept')
eq(s.w, DpsMath.MAX_W, 'width capped')
eq(s.h, DpsMath.MIN_H, 'height at least the minimum')
eq(s.tab, 'taken', 'tab kept')
eq(s.seg, 'c', 'a fight id is not kept')
eq(s.share, true, 'a bad boolean falls back')
eq(s.x, 12, 'x')
eq(s.y, 40, 'y')
eq(DpsMath.sanitize({ tab = 'nope' }).tab, 'dmg', 'unknown tab')
eq(DpsMath.sanitize({ seg = 's' }).seg, 's', 'session kept')
local x, y = DpsMath.clampPosition(-500, 900, 200, 150, 800, 600)
eq(x, 24 - 200, 'clamp x')
eq(y, 600 - 24, 'clamp y')
local w, h = DpsMath.clampSize(50, 5000)
eq(w, DpsMath.MIN_W, 'min width')
eq(h, DpsMath.MAX_H, 'max height')

-- formats
eq(DpsMath.short(999), '999', 'short')
eq(DpsMath.short(1234), '1.2k', 'short k')
eq(DpsMath.short(15000), '15k', 'short round')
eq(DpsMath.short(123456), '123k', 'short big k')
eq(DpsMath.short(2500000), '2.5kk', 'short kk')
eq(DpsMath.short(-45600), '-45.6k', 'short negative')
eq(DpsMath.exact(1234567), '1,234,567', 'exact')
eq(DpsMath.exact(123456), '123,456', 'exact no leading comma')
eq(DpsMath.duration(42000), '0:42', '42 s')
eq(DpsMath.duration(725000), '12:05', 'minutes')
eq(DpsMath.duration(3725000), '1:02:05', 'hours')
eq(DpsMath.duration(-1), '0:00', 'negative')
eq(DpsMath.perSecond(6000, 1500), 4000, 'per second')
eq(DpsMath.perSecond(6000, 0), 0, 'no time')
eq(DpsMath.percent(1, 3), 33.3, 'percent')
eq(DpsMath.percent(5, 0), 0, 'percent of nothing')

-- rows (a view as combatlog_core.lua CL.view builds it)
local view = { id = 3, label = 'Dragon +1', dur = 2000, live = 1, boss = 0, t = {
  { tot = 1000, ov = 0, el = { fire = 600, physical = 400 }, r = {
    { 's:Witchfire Bolt', 's', 'Witchfire Bolt', 'kah pyr vesh', 600, 3, 1, 300, 0 },
    { 'w:Sword attacks', 'w', 'Sword attacks', 'sword', 400, 4, 2, 150, 0 } } },
  { tot = 100, ov = 40, el = {}, r = { { 's:Mend', 's', 'Mend', 'exura', 100, 2, 0, 60, 40 } } },
  { tot = 0, ov = 0, el = {}, r = {} },
  { tot = 0, ov = 0, el = {}, r = {} },
} }
local rows, total = DpsMath.rows(view, 1)
eq(total, 1000, 'tab total')
eq(#rows, 2, 'two rows')
eq(rows[1].pct, 60, 'share')
eq(rows[1].frac, 1, 'top bar full')
eq(rows[2].frac, 400 / 600, 'second bar')
eq(rows[1].rate, 300, 'per second')
eq(rows[1].avg, 200, 'average hit')
eq(rows[2].critPct, 50, 'crit rate')
eq(rows[1].max, 300, 'max hit')
eq(DpsMath.rows(view, 2)[1].over, 40, 'overhealing')
eq(#DpsMath.rows(view, 3), 0, 'empty tab')
eq(#DpsMath.rows(nil, 1), 0, 'no view')
local els = DpsMath.elements(view, 1)
eq(els[1].name, 'Fire', 'largest element first')
eq(els[1].pct, 60, 'element share')
eq(DpsMath.title(view), 'Dragon +1  0:02 *', 'live title')
eq(DpsMath.title(nil), 'No fight yet', 'no fight')
eq(DpsMath.title({ id = 's', dur = 60000 }), 'Session  1:00', 'session title')

-- icons and colours
eq(DpsMath.iconSpec('s', 'kah pyr vesh').kind, 'spell', 'spell icon by words')
eq(DpsMath.iconSpec('r', 3155).id, 3155, 'rune item')
eq(DpsMath.iconSpec('d', 'poison').path, '/images/game/buffs/poison', 'dot: the buff icon')
eq(DpsMath.iconSpec('w', 'sword').path, '/images/game/dpsmeter/sword', 'our icon')
eq(DpsMath.iconSpec('c', 'monster').path, '/images/game/dpsmeter/monster', 'monster')
eq(DpsMath.iconSpec('o', 'zzz').path, '/images/game/dpsmeter/other', 'unknown icon')
eq(DpsMath.iconSpec('s', '').path, '/images/game/dpsmeter/other', 'spell without words')
eq(DpsMath.barColor('s', 2), DpsMath.HEAL_COLOR, 'healing bars are green')
eq(DpsMath.barColor('zz', 1), DpsMath.KIND_COLORS.o, 'unknown kind')
eq(#DpsMath.ICONS, 18, 'own icons')
for _, n in ipairs(DpsMath.ICONS) do
  local f = io.open(dir .. '../../data/images/game/dpsmeter/' .. n .. '.png', 'rb')
  eq(f ~= nil, true, 'icon file ' .. n)
  if f then f:close() end
end

-- segments
local segs = { { 's', 'Session', 90000, 5000, 100, 0, 0, 0, 0 }, { 3, 'Dragon +1', 2000, 1000, 100, 0, 1, 0, 0 },
  { 2, 'Ashen Tyrant', 61000, 3000, 0, 0, 0, 1, 0 } }
local opts = DpsMath.segmentOptions(segs)
eq(#opts, 3, 'current, session, one finished fight')
eq(opts[1].id, 'c', 'current first')
eq(opts[2].id, 's', 'session')
eq(opts[3].text, '#2 [Boss] Ashen Tyrant (1:01)', 'finished fight text')
local key1 = DpsMath.segmentKey(opts)
segs[2][3] = 9000 -- the running fight goes on: the list stays the same
eq(DpsMath.segmentKey(DpsMath.segmentOptions(segs)), key1, 'no rebuild while a fight runs')

-- party
local party = {
  { n = 'Hero', self = 1, fd = 1000, fh = 0, ft = 50, fdur = 2000, live = 1, sd = 9000, sh = 0, st = 900, sdur = 30000 },
  { n = 'Mage', fd = 3000, fh = 500, ft = 0, fdur = 2000, live = 1, sd = 4000, sh = 900, st = 0, sdur = 10000 },
}
local pr = DpsMath.partyRows(party, 1, false)
eq(pr[1].name, 'Mage', 'best DPS first')
eq(pr[1].rate, 1500, 'member DPS')
eq(pr[2].self, true, 'self flag')
eq(pr[2].frac, 500 / 1500, 'bar')
pr = DpsMath.partyRows(party, 1, true)
eq(pr[1].name, 'Mage', 'session: 400/s beats 300/s')
eq(DpsMath.partyRows(party, 2, false)[1].rate, 250, 'HPS')

-- export
local text = DpsMath.summary(view, 1)
eq(text:find('DPS Meter %- Dragon %+1 %(0:02%)') ~= nil, true, 'summary title')
eq(text:find('1%. Witchfire Bolt  600  60%%') ~= nil, true, 'summary row')
local line = DpsMath.chatLine(view, 1)
eq(line, '[Damage] Dragon +1 0:02: 1k, 500 DPS | Witchfire Bolt 60% | Sword attacks 40%', 'chat line')
eq(#DpsMath.chatLine(view, 1, 50) <= 50, true, 'chat line length')
eq(DpsMath.summary(nil, 1), '', 'no view, no text')

if fails > 0 then
  print(fails .. ' failure(s)')
  os.exit(1)
end
print('dpsmath_test: OK (' .. checks .. ' checks)')
