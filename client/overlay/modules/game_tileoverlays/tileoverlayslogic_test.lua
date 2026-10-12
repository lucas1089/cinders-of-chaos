-- luajit tileoverlayslogic_test.lua && lua5.3 tileoverlayslogic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tileoverlayslogic.lua')
dofile(dir .. 'fielddata.lua')
local TL = TileOverlaysLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(c and true or false, true, what) end

-- ------------------------------------------------------------------ protocol and the option
eq(TL.OPCODE, 156, 'opcode')
local f = io.open(dir .. '../../../../server/data/scripts/chaos/chaos_constants.lua', 'r')
if f then
  local text = f:read('*a'); f:close()
  ok(text:find('ChaosOpcodes.tileBars = 156', 1, true), 'server constant matches')
end
eq(TL.OPTION, 'fieldTimers', 'option id')
f = io.open(dir .. '../../../base-patches/0041-tile-overlay-widgets.patch', 'r')
if f then
  local text = f:read('*a'); f:close()
  ok(text:find('+\tfieldTimers = {', 1, true), 'patch 0041: dataset entry')
  ok(text:find('id: fieldTimers', 1, true), 'patch 0041: checkbox')
  ok(text:find('modules.game_tileoverlays', 1, true), 'patch 0041: apply calls this module')
  ok(text:find('"addOverlayWidget"', 1, true) and text:find('"removeOverlayWidget"', 1, true)
    and text:find('"hasOverlayWidget"', 1, true), 'patch 0041: the Lua functions')
end
eq(TL.isOn(nil), true, 'no option: on')
eq(TL.isOn(true), true, 'on')
eq(TL.isOn(false), false, 'off')
eq(TL.hello().action, 'hello', 'hello')

-- ------------------------------------------------------------------ the generated table
ok(type(TileOverlayFields) == 'table', 'field table loaded')
local n = 0
for id, def in pairs(TileOverlayFields) do
  n = n + 1
  ok(type(id) == 'number' and id > 0, 'client id ' .. tostring(id))
  ok(type(def.t) == 'number' and def.t > 0 and def.t % 1000 == 0, 'time of ' .. id)
  ok(type(def.n) == 'string' and def.n ~= '', 'name of ' .. id)
end
ok(n > 0, 'the table has fields')
local walls = 0
for _, def in pairs(TileOverlayFields) do
  if def.n == 'magic wall' then
    walls = walls + 1
    eq(def.t, 20000, 'a magic wall lasts 20 s')
  end
end
ok(walls > 0, 'magic walls are in the table')

-- ------------------------------------------------------------------ numbers
eq(TL.formatSeconds(0), '0', '0 s')
eq(TL.formatSeconds(9.7), '9', 'whole seconds')
eq(TL.formatSeconds(59), '59', '59 s')
eq(TL.formatSeconds(60), '1:00', 'a minute')
eq(TL.formatSeconds(65), '1:05', '1:05')
eq(TL.formatSeconds(720), '12:00', '12:00')
eq(TL.formatSeconds(-3), '0', 'negative')
eq(TL.secondsLeft(20000), 20, '20 s')
eq(TL.secondsLeft(19001), 20, 'rounded up')
eq(TL.secondsLeft(1), 1, 'still 1 at the end')
eq(TL.secondsLeft(0), 0, 'over')
eq(TL.secondsLeft(-50), 0, 'past')

-- ------------------------------------------------------------------ view range
local R = TL.rangeFromSize(18, 14)
eq(R.left, 8, 'left'); eq(R.right, 9, 'right'); eq(R.top, 6, 'top'); eq(R.bottom, 7, 'bottom')
R = TL.rangeFromSize(nil, nil)
eq(R.left + R.right + 1, 18, 'default width')
local P = { x = 100, y = 100, z = 7 }
ok(TL.inRange({ x = 92, y = 94, z = 7 }, P, R), 'top left corner')
ok(TL.inRange({ x = 109, y = 107, z = 7 }, P, R), 'bottom right corner')
ok(not TL.inRange({ x = 91, y = 100, z = 7 }, P, R), 'one west of the view')
ok(not TL.inRange({ x = 110, y = 100, z = 7 }, P, R), 'one east of the view')
ok(not TL.inRange({ x = 100, y = 108, z = 7 }, P, R), 'one south of the view')
ok(not TL.inRange({ x = 100, y = 100, z = 6 }, P, R), 'another floor')
ok(not TL.inRange({ x = 100, y = 100, z = 7 }, { x = 65535, y = 65535, z = 255 }, R), 'no player position yet')
ok(not TL.inRange({ x = 100, y = 100, z = 7 }, nil, R), 'no reference')
-- just after a step the place before it counts
local before, after = { x = 100, y = 100, z = 7 }, { x = 101, y = 100, z = 7 }
eq(TL.refPos(after, { at = 1000, old = before }, 1000), before, 'same frame as the step: the old place')
eq(TL.refPos(after, { at = 1000, old = before }, 1250), before, 'within the window')
eq(TL.refPos(after, { at = 1000, old = before }, 1251), after, 'after the window: the current place')
eq(TL.refPos(after, nil, 1000), after, 'no step yet')

-- ------------------------------------------------------------------ field records
local FIELDS = { [2129] = { t = 20000, n = 'magic wall' }, [2118] = { t = 360000, n = 'fire' }, [2119] = { t = 240000, n = 'fire' } }
local st = TL.newFields()
local W = { x = 102, y = 101, z = 7 }
eq(TL.fieldAdd(st, W, 1234, 0, true, FIELDS), nil, 'not a field')
local rec = TL.fieldAdd(st, W, 2129, 10000, true, FIELDS)
ok(rec and rec.start == 10000, 'a wall cast in view: exact start')
eq(TL.fieldText(rec, 10000), '20', '20 at the start')
eq(TL.fieldText(rec, 10001), '20', 'still 20 just after')
eq(TL.fieldText(rec, 11000), '19', '19 a second later')
eq(TL.fieldText(rec, 29500), '1', '1 at the end')
eq(TL.fieldText(rec, 30000), '0', '0 when it should go')
eq(TL.fieldText(rec, 32001), '~', 'outlived its time: unknown')
eq(TL.fieldColor(rec, 10000), '#ffffff', 'white')
eq(TL.fieldColor(rec, 26000), '#ffa040', 'orange in the last 5 s')
eq(TL.fieldAdd(st, W, 2129, 12000, true, FIELDS), rec, 'the same field twice counts once')
-- the tile is sent again (cleaned and filled in one packet): the timer stays
eq(TL.fieldRemove(st, W, 2129, 15000), rec, 'removed')
eq(st.recs[TL.recKey(W, 2129)], nil, 'no record')
local back = TL.fieldAdd(st, W, 2129, 15000, true, FIELDS)
eq(back, rec, 'put back at once: same record')
eq(back.start, 10000, 'same start')
-- it really goes and a new one is cast later: a new timer
TL.fieldRemove(st, W, 2129, 30000)
TL.fieldSweep(st, 30300, P, R)
eq(next(st.ghosts), nil, 'ghost gone after the grace')
local again = TL.fieldAdd(st, W, 2129, 31000, true, FIELDS)
ok(again ~= rec and again.start == 31000, 'a new wall: a new timer')
-- a wall that came into view with its tile: unknown
local far = { x = 109, y = 100, z = 7 }
local u = TL.fieldAdd(st, far, 2129, 31000, false, FIELDS)
eq(u.start, nil, 'came into view: no start')
eq(TL.fieldText(u, 31000), '~', 'shown as ~')
eq(TL.fieldColor(u, 31000), '#bfb6a6', 'grey')
-- put back within the grace but the tile came into view (a re-description after a teleport): stays unknown
TL.fieldRemove(st, W, 2129, 32000)
local re = TL.fieldAdd(st, W, 2129, 32000, false, FIELDS)
eq(re.start, nil, 'came into view again: unknown, the old timer is not trusted')
-- a field that decays into its next stage: a new record with the stage's own time left
local F = { x = 103, y = 101, z = 7 }
local f1 = TL.fieldAdd(st, F, 2118, 0, true, FIELDS)
eq(TL.fieldText(f1, 0), '6:00', 'fire: 6 minutes in all')
TL.fieldRemove(st, F, 2118, 120000)
local f2 = TL.fieldAdd(st, F, 2119, 120000, true, FIELDS)
eq(TL.fieldText(f2, 120000), '4:00', 'next stage: 4 minutes left')
-- sweep: records out of view are dropped
local dropped = TL.fieldSweep(st, 120000, { x = 130, y = 100, z = 7 }, R)
ok(#dropped >= 3, 'walked away: records dropped')
eq(next(st.recs), nil, 'nothing left')
eq(TL.fieldAdd(st, { x = 1, y = 2 }, 2129, 0, true, FIELDS), nil, 'bad position')
eq(TL.fieldRemove(st, W, 2129, 0), nil, 'removing what is not there')

-- ------------------------------------------------------------------ server bars
local store = {}
local set, del = TL.applyBars(store, { s = {
  { i = 'bg:1:1', p = { 100, 100, 7 }, n = 'West Well', c = '#FF9A3C', v = 0.25 },
  { i = 'prof:5:x', p = { 101, 100, 7 }, n = 'Ready in', c = '#7fb069', l = 90000, t = 360000 },
  { i = 'junk', p = { 1, 2 } },
  { p = { 1, 2, 3 } },
  'x',
} }, 1000)
eq(#set, 2, 'two bars set, junk ignored')
eq(set[1], 'bg:1:1', 'sorted')
eq(#del, 0, 'none dropped')
local b1, b2 = store['bg:1:1'], store['prof:5:x']
eq(b1.color, '#ff9a3c', 'colour lower case')
eq(TL.barProgress(b1, 1000), 0.25, 'progress')
eq(TL.barText(b1, 1000), 'West Well', 'label')
eq(b2.endMs, 91000, 'countdown end on the client clock')
eq(TL.barProgress(b2, 1000), 0.25, 'countdown part left')
eq(TL.barText(b2, 1000), 'Ready in 1:30', 'countdown text')
eq(TL.barText(b2, 61000), 'Ready in 30', 'countdown text later')
eq(TL.barProgress(b2, 100000), 0, 'countdown over')
eq(TL.barText({ label = '', endMs = 5000, totalMs = 5000 }, 0), '5', 'countdown without a label')
eq(TL.parseBar({ i = 'x', p = { 1, 2, 3 }, v = 7, c = 'blue' }, 0).v, 1, 'progress clamped')
eq(TL.parseBar({ i = 'x', p = { 1, 2, 3 }, c = 'blue' }, 0).color, TL.DEFAULT_COLOR, 'bad colour')
eq(TL.parseBar({ i = 'x', p = { 1, 2, 99 } }, 0), nil, 'bad floor')
eq(#TL.expiredBars(store, 92000), 0, 'not expired within the grace')
local ex = TL.expiredBars(store, 93000)
eq(ex[1], 'prof:5:x', 'expired countdown')
set, del = TL.applyBars(store, { s = { { i = 'bg:1:1', p = { 100, 100, 7 }, n = 'West Well', v = 0.5 } }, d = { 'prof:5:x', 'nope' } }, 2000)
eq(#set, 1, 'update')
eq(store['bg:1:1'].v, 0.5, 'updated progress')
eq(#del, 1, 'dropped one (the unknown id is ignored)')
eq(store['prof:5:x'], nil, 'dropped')
set, del = TL.applyBars(store, nil, 0)
eq(#set + #del, 0, 'junk message')
-- layout
eq(TL.fillWidth(0.5, 64), 32, 'half')
eq(TL.fillWidth(0, 64), 0, 'empty')
eq(TL.fillWidth(1.4, 64), 64, 'clamped')
eq(TL.fillWidth(0.004, 64), 0, 'rounded')
store['bg:1:0'] = { id = 'bg:1:0', pos = { x = 100, y = 100, z = 7 }, label = '', v = 0 }
store['other'] = { id = 'other', pos = { x = 100, y = 101, z = 7 }, label = '', v = 0 }
local s = TL.stack(store, { x = 100, y = 100, z = 7 })
eq(#s, 2, 'two bars on the tile')
eq(s[1].id, 'bg:1:0', 'by id')
eq(s[1].index, 1, 'first is the lowest')
eq(s[2].index, 2, 'second above it')
local cx, cy = TL.centre(64, 64)
eq(cx + cy, 0, '64 px tiles: no correction')
cx, cy = TL.centre(80, 80)
eq(cx, 8, '80 px tiles: 8 px right'); eq(cy, 8, 'and down')
cx, cy = TL.centre(32, 32)
eq(cx, -16, 'small tiles: back')
eq(TL.barLift(64, 1), 32 + TL.BAR.h / 2 + 4, 'lowest bar just over the tile')
eq(TL.barWidth(20), TL.BAR.w, 'short text: the usual width')
eq(TL.barWidth(80), 92, 'long text: wider')
eq(TL.barLift(64, 2) - TL.barLift(64, 1), TL.BAR.h + TL.BAR.gap, 'stacked')
ok(TL.barLift(80, 1) > TL.barLift(64, 1), 'grows with the zoom')

print(string.format('tileoverlayslogic_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
